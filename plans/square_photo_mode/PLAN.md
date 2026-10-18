# Photo Mode (`square_photo_mode`)

Public name (modinfo, 13 languages): "Photo Mode: Aerials & Camera"; the short name "Photo Mode" stays for the
window title, the top-bar tooltip and the cover title (`branding/mods.js` `shortName` / `titleLines`).

Status: rev 1 built 2026-10-12, unreleased; rev 2 phase 1 (camera window) built 2026-10-12. First in-game run
2026-10-13 (`.cache/logs/2026-10-13_0325_session`): boost, window, subjects, shots, orbit, tour, saved views worked;
the user's feedback (9 items, "Rev 1 feedback" below) built in code 2026-10-13. The graphics switch crashed the
renderer twice (`2026-10-13_0342_sqot` window-first, `2026-10-13_0356_top-up-779299` switch-first); redesigned
the same day: the button only opens the window, a "Highest graphics" toggle in the window switches in 5 stages
("Highest graphics: the staged switch" below). Second in-game run 2026-10-13 (`2026-10-13_0418_session`): the
staged switch worked 4 of 4 (~20 min into the session), tours of saved views and random subjects ran; every
one-call restore logged 2x "Could not invert matrix". The user's second feedback round (10 items, "Rev 1
feedback round 2" below) built in code 2026-10-13, untested (TESTING.md G1-G10, S1-S12). Two more renderer
crashes (`2026-10-13_0522_sqrl-sqsg-crash`, `2026-10-13_0524_sqrl-sqsg-crash`), each right after stage 4
(`shadowQuality`): changing shadows at runtime is the trigger (findings map-camera.md "Changing render-buffer
settings at runtime crashes"). Round 3 ("Rev 1 feedback round 3" below, built in code 2026-10-13, untested): shadows are
never touched (4 stages), a narrow window, even spacing, Hide UI a checkbox until Esc, a framed Start tour.
Round 4 ("Rev 1 feedback round 4" below, built in code 2026-10-13, untested: TESTING.md G16-G20, L1-L9): horizon
shots and a horizon tour range, mouse look while flying, the pause-key escape while the UI is hidden, and phase 3
(the Light tab: light and weather override, freeze). One more crash (`2026-10-13_0558_session-crash`, fatal
assert `StaticBuffer.cpp:743` right after stage 2 `geometryQuality,terrainQuality,grassQuality`): round 5 ("Rev 1
feedback round 5" below, built in code 2026-10-13, untested) raises only keys that reload images / screen
effects (textures, SSAO, reflections, MSAA, resolution scale) in 3 stages; findings map-camera.md "Changing
render-buffer settings at runtime crashes".
Round 6 ("Rev 1 feedback round 6" below, built in code 2026-10-13, untested: TESTING.md G21-G28): the layout
fixed at its root (inline styleSheets on layouts never applied; class rules now), a "This place" tour, "Hide
labels and hover", camera mode (the game's free camera) for tours and as a footer button instead of Hide UI,
tour performance options.
Round 7 ("Rev 1 feedback round 7" below, built in code 2026-10-13, untested: TESTING.md R1-R10), from session
`2026-10-13_0733_bench-s3-683079`: every automated camera move planned in eye space (the eye no longer bobs with
the terrain under the look-at point), Ken Burns with a random pace and vertical moves, a "Wander" camera move and
tour mode, Bird's eye at 1.30 (1.45 inverted the WASD keys), tooltips on every control, the range rows renamed
"Angle from / to" and "Distance from / to", camera mode for tours experimental and off by default (setCameraData
most likely doesn't drive the free camera).
Round 8 ("Rev 1 feedback round 8" below, built in code 2026-10-13, untested: TESTING.md U1-U12), from session
`2026-10-13_0856_sqot-dev` and a Subjects tab screenshot: outlined, compact buttons in grids of equal cells and a
Mode dropdown instead of rows of borderless buttons, the footer padded for real (padding on Components, not
layouts), the height bumps traced to a pitch offset of the game's camera (eye ~0.25 rad steeper than the pitch
set; measured live and compensated, with a per-frame trace), saved views in the pool of the tour's shots and
Anything.
Round 9 ("Rev 1 feedback round 9" below, built in code 2026-10-13, untested: TESTING.md V1-V10), from session
`2026-10-13_1755_session`: the map's hover, tooltips and click-to-select off during every automated move (tours,
Wander, Orbit); "Try camera mode during tours" and its probe removed; the game's camera model fitted from the
trace (centre 4 m above the ground; the eye's elevation the pitch blended towards straight down by a factor that
grows with the distance) and used per frame, so glides and the Wander no longer jerk over uneven ground; an "eye
smoothness" log line per hop / wander stretch / move.
Round 10 ("Rev 1 feedback round 10" below, built in code 2026-10-13, untested: TESTING.md W1-W9), from session
`2026-10-13_1915_session`: hover and money floaters during tours traced to the default selector being the default
TOOL's action (our own empty tool now pushed on the tool stack while hover must be off); the camera model refitted
up to 1725 m (a distance-dependent lift; the centre sinks to the water level past 800-1500 m), which explains and
fixes the Aerials' jerk and round 7's Bird's eye; a "Smooth camera" on the normal camera (strength, Level zoom);
the footer's "Camera mode" is now "Free camera".
Phase 4 (looks, weather over time, time-lapse, seasons, sun placement; `LOOKS.md`, built in code 2026-10-13,
untested: TESTING.md K1-K13): eight looks per base climate as 32 generated env files switched rendering-only,
storm / clearing / low cloud animations, sunrise / sunset / run-the-clock time-lapse, winter / summer sun,
Backlight / Side / Front light from the camera's heading; sections of the Light tab (not a sixth tab: the tab
labels would not fit 440 px in de / nl). Probe facts behind it: `docs/findings/environment.md`.
Round 13 ("Round 13" below, built in code 2026-10-14, untested: TESTING.md CB1-CB8), from session
`2026-10-14_0434_session`: the Smooth camera removed; the free camera's mouse attachment no longer toggled and the
view tool's right-click back only during moves (the "hyper sensitive" report); the eye spikes measured at the
frames' own times (none left the camera model; long frames and the player's input); a DEV orbit cutscene attached
to a subject; the game's Advanced Camera Tool found as the native keyframed path (the player tries it first).
Round 14 ("Round 14" below, built in code 2026-10-14, untested: TESTING.md CC1-CC5), from session
`2026-10-14_0633_session`: the renderer's tool actions off during automated moves (the base cutscene's switch: the
hover outline the empty action left), shot presets framed from one anchor (Eye level -> High horizon -> Eye level
comes back), the DEV orbit's keys with the game's own speeds (the pulse) and locked to the anchor, the Down look's
10 spike reports classified and a "centre fit" tally (base height / water) for the next round, a 1 s blend.
Round 15 ("Round 15" below, built in code 2026-10-14, untested: TESTING.md CD1-CD6), from session
`2026-10-14_0658_session`: round 14's `disableToolActions` let the default selector's clicks through (a world lock
instead: the base selector entity filter, no entity windows, our empty action kept on top); High the default
Aerials look; no free camera control exists (binary strings); the "hyper sensitive" camera traced to far, flat
views handed back (the keyboard pan scales with the distance; `hand-back` lines); a DEV cutscene aerial (keys
attached to one placeholder each, anchors chosen by the GUI, chained flights).
Round 16 camera ("Round 16 camera" below, built in code 2026-10-14, untested: TESTING.md CE1-CE6), from the user's
round 15 run (its log lost): Aerials keeps its picture on the map (DEV flights turn away from the edge, tours keep
a view margin), goes over places not shown lately, a far / flat view eases in after a move (the fast pan), Orbit
eases in and out, a DEV cutscene orbit around a static anchor at the view's centre.
Round 16 settings ("Round 16 settings" below, built in code 2026-10-14, untested: TESTING.md RS1-RS12): saved
setups of the whole picture (the Settings tab; settings.lua, every savegame) and "Restore last setup" after an
accidental Esc; three live cloud sliders (cover, height, density) since a look's strength can't be live (1076 files
already fill the budget); the base game's Legacy atmosphere as a whole look (no files); brighter windows and lamps
in Moonlit night and Neon dusk.
Round 17 lens / animals / orbit ("Round 17: lens, animals, orbit" below, built in code 2026-10-14, untested:
TESTING.md LA1-LA8, LT1-LT6, AG1-AG6, OR1-OR3), from `2026-10-14_0842_session`: the Lens looks at its anchor (the
look missed by the anchor's yaw), never stops on its own, a World speed choice and a lens tour; animal groups placed
where their suitableAreas score allows; Orbit circles the middle unless the jumped-to subject is still there; Dust
removed.
Round 18 ("Round 18" below, built in code 2026-10-14, untested: TESTING.md R18-1..R18-7), from
`2026-10-14_1729_add-money-100m`: a cutscene bar (1x / 2x / 4x, Stop) by wrapping the base FreeCamOptions; F9 found
to work during a cutscene; lens keys with every lock off (pitch), neighbouring buckets and a looser aim (17 of 29
starts were refused); the base spin box arrows on the step buttons (the notch); "Hide labels" renamed; DEV risky
graphics (shadow / geometry / terrain / grass, one key at a time).
Round 19 ("Round 19" below, built in code 2026-10-14, untested: TESTING.md R19-1..R19-5), from
`2026-10-14_2019_r18-test`: no animal limit and a per-species list; the lens tries tighter / wider frames (off-map
400 mm shots and orbits, landscape) and falls back to the nearest object; Vehicle Ride along / Steady (no easing
exists); the arrow buttons draw the compact contour inline.
Round 20 ("Round 20" below, built in code 2026-10-14, untested: TESTING.md R20-1..R20-9), from
`2026-10-14_2150_r19-test`: DEV risky graphics removed (High graphics mode raises geometry / terrain / grass) and a
shadows note on the Settings tab; an Animals tab (more groups, horses, Distance / Formation / Facing, placed by
screen rays so they show, never refused for the spot); a saved views description; a jump follows its vehicle;
the subject orbit at half speed; the game speed watched after a cutscene end (it paused); the lens eye within
1.5 km (telephoto haze and LOD).
Rev 2 ships as rev 1 (nothing uploaded yet).

## What it does

A camera button in the top-left mod button bar opens and closes the Photo Mode window (tabs Subjects, Camera,
Views, Tour, Light: subjects and photographer's shots to jump to, shot presets (horizon shots included), camera
moves (Orbit, Wander, Follow, Cockpit), saved views, tours on the ground or by drone (mouse look while flying),
around one place (shots or a Wander drift), time of day, weather and a freeze; phase 4: looks, weather over
time, time-lapse, winter / summer sun and sun placement in the Light tab); no graphics change on open /
close. Closing the window stops every camera move. In
the window's footer (under the tabs, on every tab): a "High graphics mode" checkbox sets textures, terrain
textures, SSAO, reflections, MSAA and resolution scale to their highest (in 3 stages) and back (in 3 stages); a "Hide labels" checkbox (round 18 name; "Hide labels and hover" before) hides the map's HUD
labels (the base HUD filter) and the hover / selection (round 6); a "Free camera" button (the game's free camera, the game hides its UI, Esc returns; round 6's "Camera mode", replacing the Hide UI checkbox). High graphics and hidden labels stay on
when the window closes; the button shows the high graphics (green contour, a tooltip
line). The player's own settings and labels come back when they untick them or the pause menu opens. No
options for "how high": always the maximum.

Highest values (`pm_core.lua` `BOOST`): `textureQuality` 2, `terrainTextureQuality` 2, `numMSAASamples` = the
highest of `app.getSupportedMSAASampleCounts()` (fallback 4), `useSsao` true, `ssrQuality` 2,
`resolutionScale` 1.0. `vsync`, `cameraTool`, `shadowQuality`, `geometryQuality`, `terrainQuality` and
`grassQuality` are not touched (render-buffer settings: a runtime change crashed the game, shadows 4 times,
geometry / terrain / grass once; never snapshotted, restored or recovered; an old marker that still holds them is
accepted, those values ignored; findings map-camera.md "Changing render-buffer settings at runtime crashes"). Geometry tiers (draw distance, LOD scaling) are left alone: writes stick but show nothing
(`docs/findings/map-camera.md` "Geometry tiers").

## Files

| File | Role |
|---|---|
| `content/photo_mode/pm_core.lua` | pure logic: keys, boost values, the 5 switch stages + delay, snapshot, marker parse + value validation, recovery choice, switch gate, safe format (offline tests) |
| `content/photo_mode/gui/pm_button.script.lua` | `::MainModButtonAreaExtension` plugin: button (window open / close), the staged highest-graphics switch and its restore, pause-menu restore, safety net, the frame rule (no window open / close in a switch frame) |
| `content/photo_mode/gui/pm_button.res.lua` | plugin registration (order 40, after Stress Test's 30) |
| `content/photo_mode/pm_place.lua` | pure (round 6): the "This place" tour's shots: heading slices per round, pitch bands, distances by the area, nearby subjects as targets |
| `content/photo_mode/pm_cam.lua` | pure camera logic (round 14: `shotAnchor`, the shot presets' shared anchor): framing (subjects, tour within a range), shots, glide, orbit, moved check, picks, weighted "Anything" order, tour order, tour range / presets / modes, look offset, terrain clearance, random points, bookmarks (names, reorder), safe views; round 15: `AERIAL_LOOK_DEFAULT` (High) |
| `content/photo_mode/pm_shots.lua` | pure: the photographer's shots' scores (bridge height, tunnel boundary, approach, departure, oldest), searches (closest pair, densest cell, main axis, skyline / viewpoint picks) and framings (a look heading, not a camera angle) |
| `content/photo_mode/pm_variety.lua` | round 17, pure: variety for repeated jumps: a bag per pick kind (`newBag`, `isFresh`, `take`: the cycle of subjects shown, the view variant; `choose`: shuffle bag for the saved views) and view variants (`vary`: golden-angle heading steps, eye / high / low styles, distance jitter; `same`, `distinct`: never the identical view twice in a row) |
| `content/photo_mode/pm_flight.lua` | round 10: the refitted camera model (`camK` returns k1, k2; `centreKeep` / `centreZ(g, d)`: the centre sinks to the water level far out; `pitchMaxAt`), `solveEye` on the distance-dependent centre surface with a last-resort bisection (`EYE.guardIters`, `st.guarded`), cuts in the smoothness metric (`smoothCut`, `SMOOTH.cutSpeed`), round 13: the smooth camera removed, d2 at the frames' own times (`lastD2Raw` the plain one), the Aerials High look (`HIGH`, `highPose`: the look-at point 1.6 km+ out on the sea); pure: speed ramps, the velocity-continuous hop (glide between drifting end points, hold from the arrival), Ken Burns drift rates (round 7: a main move, random pace), the Aerials flight (Catmull-Rom path, waypoint choice inside the map, drone view, altitude), round 7: eye space (`poseOf`, `viewOfPose`, `solveEye`: the view to send for an eye pose, clearance lift, `rayInside`), Wander (eye path, look targets, `wanderView`); round 9: the game's camera model (`centreZ`, `camK`, `gameElev`, `pitchFor`; `pitchSample` / `resSample` / `resUpdate`: the model's residual, a critically damped follower; `solveEye` against the centre surface, the plan-based flattest-look bound, the jump blend; `poseOf` gamePitch, `elevView` / `gameView`, `eyeOf`), the smoothness metric (`newSmooth`, `smoothAdd`, `smoothStats`) |
| `content/photo_mode/gui/pm_hud.lua` | round 10: our view tool `SquarePhotoModeView` (react.RegisterTool, pushed on the default tool stack while an automated move runs, or labels are hidden; popped when nothing needs it; noticed when another tool clears it; round 13: its action's right-click back only during a move, the smooth camera and its click selector removed, the free camera's mouse attachment never toggled; round 14: the renderer's tool actions off during automated moves, `setActionsOff`, the base cutscene's `disableToolActions`, back on every exit); Hide labels and hover (base HUD filter in GUI save data + the selector kept prevented + our safety marker), camera mode (the base FreeCamTool on the default tool stack: the footer button), Hide UI (the fallback: ui root, until the pause menu or the pause key: the escape hatch reads the game speed while hidden), the tour's window / UI / labels; restored on the pause menu and at every start; round 9: hover off during automated moves (`setAutoHover`: prevent at the start and 2 / 30 frames later, allow at the end unless the labels keep it), tours never push the free camera (the probe removed; only the footer button uses it); round 15: the world lock during automated moves and cutscenes (`lockWorld`: the selector entity filter, entity windows off, our tool pushed back on top), `disableToolActions` no longer fired |
| `content/photo_mode/gui/pm_world.lua` | round 14: `baseGroundAt` (getBaseHeightAt), `waterAt` (isOnWater) for the centre fit; subjects on the map: cached entity lists, positions, random places, the photographer's shots (SHOT: budgeted scans and terrain samples), flight waypoint candidates; round 8: the "saved" kind (a random saved view, `savedViews` set by the driver); round 15 DEV: `flyCandidates` (anchors with a fat model instance from the octree), `flyStatsText` |
| `content/photo_mode/gui/pm_driver.lua` | round 10: the residual from 0 per move, every pitch sent capped (`F.pitchMaxAt`), `cuts=` / `guarded=` in the smoothness lines, round 13: the smooth camera removed, the eye spike metric at the frames' own times (`S.prevDt`, look jolts, `read-sent=`; item 5: one report per jolt, 8 a move, 24 a session, `spikes=`), Aerials the default tour mode, the High look in `flightView`, the DEV orbit cutscene (Orbit after a jump, `D.cutsceneOrbit`); round 14: shots framed from the anchor (`S.shotAnchor`, `resetShotAnchor`), the "centre fit" tally (`centreFit`, one line per move; `base=` / `water=` in spike reports), the orbit's pace (`orbitPace`, `paceText`, `heading=` / `rel=`); camera driver: look calibration, jump (framings, terrain clearance, followed shots), shot, orbit, wander (round 7), follow (+ staged release), cockpit, tour (hops, flights, modes; step from onStep); round 7: every automated move sent through the eye-space solver (`sendPlanned`), "eye check" log lines; round 8: the pitch offset measured each frame of a move and compensated, `cam trace` lines, saved views as subjects; round 9: the camera model's residual per frame (`sampleCam`), traces of every Wander (40 frames + bursts at 600 / 1800 / 3600), `eye smoothness` lines (per hop, flight leg, 30 s of wander, move total), `D.onAutoMode` (hover) synced in `bump`, `switching` (no hover flicker when one move replaces another); the camera mode hook removed; round 15: `hand-back` lines, `camera set with no move active`, a cutscene counts as an automated move, DEV: the cutscene aerial chain (`cutsceneFly`, `flyStep`) on Start in Aerials |
| `content/photo_mode/gui/pm_window.lua` | the window: tabs Subjects / Camera / Views / Tour / Light (labelled rows, ToggleButtonGroups, checkboxes, one Start / Stop button), footer (High graphics mode, Hide labels and hover, the Free camera button; round 13: the Smooth camera button and the Camera tab's Smooth camera section removed); phase 4: the Light tab's Looks / Weather over time / Time-lapse / Season and sun sections (`looksRows`), status line, saved-views table, our GUI save data (views + labels marker); round 8: outlined compact buttons, grids of equal cells, the Mode dropdown, content and footer padded by Components; round 16: the Settings tab's saved setups (`setupsSection`, `setupTip`), the Weather tab's cloud sliders (`cloudStep`), `last` in our save data; round 20: the Animals tab (eight tabs, 16 px icons), the Settings tab's shadows note, the Views tab's description |
| `content/photo_mode/pm_light.lua` | pure: light / weather presets (sun times from day of year and latitude), step wrapping, override bookkeeping (orig / set), the save-data marker, the restore plan (only what is still ours); round 16: the cloudScattering field, the cloud sliders' scales (`SLIDER` cloud / cloudBase / cloudScattering, `sliderChanges`: the deck keeps its thickness) |
| `content/photo_mode/pm_looks.lua` | phase 4, pure: climates, looks, ResNames, climate detection, easing, weather / time-lapse plans, solar geometry, sun placement, start plan; round 16: whole looks (`WHOLE`: Legacy = the base `<c>_old.env`), the Sky menu `MENU` (the arrows step through it) |
| `content/photo_mode/gui/pm_weather.lua` | phase 4: look switch / restore (rendering only), weather animations, time-lapse, seasons, sun placement, pause menu, game start (through pm_sky) |
| `content/environments/sqpm_<climate>_<sky>_<haze>_<water>.env.lua` | phase 4: 1076 generated look environments (round 15: 4 base climates x (9 skies x 6 hazes x 5 waters - 1), 4.5 MB; round 12: 396, round 11: 136, phase 4: 32), `tools/gen_photo_looks.py [--check]` |
| `content/photo_mode/gui/pm_slider.lua` | round 15: the Light tab's slider row recipe (own react state, throttled quiet live writes through pm_sky.setLive, a final pm_sky.set at the release or after 400 ms) |
| `content/photo_mode/pm_setup.lua` | round 16, pure: saved setups (look keys, the override's values, freeze, High graphics mode, labels): `valid`, `cleanName`, the library (`readLibrary` / `libraryData`, add / overwrite / rename / remove, CAP 30), `withKey` (a full mainMenuState copy, our `KEY` only), `capture` (named: the values always; last: only under the override), `active`, `same`, `text` |
| `content/photo_mode/gui/pm_setups.lua` | round 16: the library in `AppConfig.mainMenuState["square_photo_mode_setups"]` (read once, written by the plugin's onStep through `flush`), the last setup (captured on every click change and before the pause menu / an untick puts values back; our GUI save data `last`), `apply` (look, values, freeze both ways, HQ / labels only on), `start` |
| `tests/square_photo_mode/test_setups.lua` | round 16: pm_setup records / library / mainMenuState / capture; the cloud sliders' scales; Legacy ResNames; pm_setups through pm_sky / pm_weather on a fake api: library in settings.lua next to other mods' prefs and read back, an unreadable mainMenuState, load (look, values, density, freeze, HQ / labels only on), the pause menu and Restore last setup, look-only last, the untick, the game start, an unknown climate, Legacy switching and its end |
| `tests/square_photo_mode/test_looks.lua` | phase 4: pm_looks pure maths and pm_weather through pm_sky on a fake api |
| `content/photo_mode/gui/pm_sky.lua` | the Light tab's override (game_time.gs cycles, time of day, environment copy for clouds / day / sun, the sim's cloud cover) and freeze (game speed); restore on untick / pause menu / next load; phase 4: forwards step / pause menu / start / marker field `look` to pm_weather, facade `looks / look / weather / lapse / season / placeSun / status`; round 16: cloudScattering, the `noteChange` / `beforeRestore` hooks of gui/pm_setups.lua, quiet live cloud writes |
| `content/photo_mode/gui/pm_cutscene.lua` | round 13, DEV only (the `square_photo_mode_dev` presence marker): the orbit attached to a mapped entity (`ORBIT`, `ANCHOR`, `anchorFor`: a carriage or model entity, `entityMap`, `playOrbit`, `attachVerdict`, `abort`: the stop file; CB2), `finish` (tool actions back). The round 12 keys-file flight (CA6) is retired (no `io` in the GUI state). Round 15: the cutscene aerial (`FLY`, `flyHeading` / `flyIndex` / `flyFile`, `planFly`: anchors one leg apart along a heading, `flyMap`, `flyEyeAt`, `flyText`, `playFly`, `elapsed`; CD4) |
| `square_photo_mode_dev/content/mission/keyframes[/en]/sqpm_fly_<0-7>_<0-4>.lua` | round 16: one per heading and turn (line 1 `local HEADING, TURN = h, t`, t -2..2: the keys turn from h to h + t x 45 degrees); round 15, DEV mod: one straight flight per heading (45 degrees apart), key i attached to placeholder `FLY.anchorBase + i - 1`, `FLY.height` straight above it; identical but for line 1 (`HEADING`); both copies equal |
| `content/mission/keyframes[/en]/sqpm_orbit.lua`, `sqpm_stop.lua` | round 14: the orbit's keys with the game's Auto Set Speed (`autoSpeed`) and yaw / pitch / roll locked; round 13, DEV: the keyframe files those play (the orbit; a 0.1 s still frame played over an orbit that isn't attached) (two identical copies each: the `en/` one is what `resolveLanguageFolder` picks); inert without the DEV mod Round 17: lockYaw false (the look turns with the anchor). |
| `content/photo_mode/pm_lensdef.lua` | round 16b, pure: the Lens's lenses (12-400 mm, fovY = 2 atan(12 / mm)), size / elevation / heading buckets, the keys (hold, orbit), the plan from the player's eye and the anchor (terrain clearance), the yaw-turned reading, the fov from two projected points; the single source of the generated files Round 17: 24 headings in the anchor's frame (opts.yaw), 5 elevations, lockYaw false, the map's edge, `centreError` / `choose` (the anchor whose shot centres the player's view). |
| `content/mission/keyframes/en/sqpm_lens_*.lua`, `sqpm_lensorbit_*.lua` | round 16b: GENERATED by `tools/gen_lens_keyframes.py` (`--check`) from pm_lensdef: 1044 holds + 87 orbits = 1131 files, 1.7 MB, `en/` only; every key attached to placeholder 9999800. `sqpm_stop.lua` is now also played by the (production) Lens when its attachment doesn't resolve Round 17: 3480 holds + 145 orbits = 3625 files, 4.6 MB. |
| `content/photo_mode/gui/pm_bar.res.lua`, `pm_bar.script.lua` | round 18: the cutscene bar. A `react-replacement-config` wraps the base `FreeCamOptions` recipe (GameUIProxyRoot, outside the UI root a cutscene hides): the original unchanged plus a small bar (camera icon, 1x / 2x / 4x through `driver.screenshot`, Stop through `pm_lens.stopFromBar`) while `driver.S.cutscene` is set; inline styles only; our part in pcall |
| `content/photo_mode/gui/pm_lens.lua` | round 16b: the Lens's play (anchor at the view's centre, plan, playCutscene with the entity map), its per-frame step via `driver.S.cutscene.step` (check, fov line, screenshot, the end with the player's game speed) and the Camera tab's Lens rows Round 17: anchors out to 1 km chosen by aim error, the World speed choice, the lens tour, no automatic stop, every early end's reason. |
| `content/photo_mode/gui/pm_foreground.lua` | round 16b: the Weather tab's Foreground: low cloud veil and rain through pm_sky (`K.set` / `K.setLive`, so every override exit restores them); restore on untick / pause menu (round 17: Dust removed) |
| `content/photo_mode/gui/pm_animals.lua` | round 16b / 17: Animals: group presets (herds, packs, flocks, schools, lone predators), spots scored with the models' `suitableAreas` (`M.score`), `makeAnimalSpawnAtCmd` per animal with its callback, life checks every second (round 19: sliced, 40 a frame), `makeCustomEntityDestroyCmd` for ours, 20 a click (round 19: no session limit; the per-species list). Round 20: its own tab (pm_window `animals`), every group (the climate's first; horses), placement by screen rays (`M.march`, `M.middle`, `M.place`: Distance / Formation / Facing), the score only prefers a spot |
| `tests/square_photo_mode/test_cutscene.lua` | round 13: the orbit file (attached keys on a circle looking at the anchor, both copies equal, no math = a fixed square), the anchor (a vehicle's carriage, a carriage, a model entity, a station's construction; components as userdata-like proxies; nil for a bare transport vehicle), the map `{ [C.ANCHOR] = anchor }` handed to playCutscene, the attachment verdict, the stop file |
| `content/photo_mode/gui/pm_perf.lua` | the two SQPERF instruments of the GUI state (see "Performance") |
| `content/sqperf/square_photo_mode.lua`, `..._types.d.tl` | SQPERF copy (`make sqperf-sync`, never edit here) |
| `content/photo_mode/gui/pm_button.css.lua` | 10 rules (root margin, window position, wrapping texts, wrapping Tour labels, saved-views scroll area, the spacing classes `sqpm-gap` / `sqpm-checks` / `sqpm-content`, round 8: the compact button padding `sqpm-small` / `sqpm-cell` and the grid cell's label) + the 4 shared layer window offset rules only when no other top-bar mod adds them |
| `content/photo_mode/gui/camera@2x.tga` | white 48x48 camera mask, `tools/render_icon_ridge.py` |
| `content/square_ridge/marker.gres.lua` | ridge marker, identical to the other top-bar mods |
| `tests/square_photo_mode/test_button.lua` | pm_button on fake react / api / window: the button opens / closes the window with no setAppConfig; staged order (marker saved in stage 1's frame before it, stages 1-3 one call each, STAGE_DELAY_FRAMES apart; stages with nothing to change skipped); toggle off mid-sequence and before stage 1; pause menu mid-sequence and when on (restore at once, no window close); an off inside a stage's stall; window close (button, X) keeps HQ; button state (pressed = window, contour + tooltip = HQ); no window open / close in a switch frame; a stage waits a frame after the X; round 2: the staged restore (reverse order, delay frames apart, marker cleared with the last), the marker kept mid-restore, pause menu during the restore (one call), ticked again during the restore |
| `tests/square_photo_mode/test_core.lua` | recovery keys, marker, mainMenuState copy, snapshot, MSAA max, stages cover every key once, stageChanges, restore stages / restoreChanges, hidden HUD filter, deepCopy; crash guards: value validation, corrupt markers, gate, safe format |
| `tests/square_photo_mode/test_cam.lua` | pm_cam: framing, shots, glide, orbit, moved check, rng / picks, tour, bookmarks; feedback: name cleaning (UTF-8 cut), rename / reorder / round trip, cap 50 + duplicate ids, tour framing range, Ken Burns params / path, weighted order; crash guards: safe views, NaN / inf / 0, bounds, corrupt bookmarks; round 3: tour sources (ticked, in turn, skip, last stays), legs, flight subjects, waterKind |
| `tests/square_photo_mode/test_driver.lua` | pm_driver on a fake camera API: jump, airborne follow, orbit stop, tour glide, cockpit, idle step, scratch views, setCameraData failure; feedback: hold drift, saved-views tour order / loop / reorder / empty, staged follow release (+ give-up, jump, photo mode off), Anything; round 2: hop glide / hold timer from the arrival / drift on and off / next hop from the drift, saved-views hops, tour range, tour window hiding, Aerials flight (from rest, finite, inside the map, eye above ground, stops on input), Mixed legs end at rest, look calibration, terrain clearance, followed fastest shot, random place; crash guards: gone subjects, clamped / NaN views, game-ended cockpit, dt 0; round 3: sources in turn, last source / subject kept, Aerials next leg over a new area, flights ask for the ticked subjects; round 6: tour options (camera mode / labels / pause) to the hud, This place (around the place, every slice, subjects refreshed and targeted, a gone subject skipped, the mode kept), the camera mode hook (skip / reset / left), flight candidates once per leg with the whole leg planned; round 7: a tour glide over bumpy ground (the game's eye smooth, height reads per frame), Wander as a camera move (no cuts, around the place, stops on input, Orbit swaps) and as a tour (look targets, keeps its mode); round 9: the camera model fake (the residual measured, the eye as smooth as the plan over bumpy ground, a refused sample), traces (first move, every wander with a burst), eye smoothness lines, hover on / off on every path (tour, wander, orbit, replacing, pause menu, pause key) |
| `tests/square_photo_mode/test_world.lua` | pm_world on a fake engine: list TTL, no list copy, scan budget / continuation / kept best, one read per pick, MODEL_PERSON tried once, Anything; round 2: bridge (highest), water, passing, tunnel portal, platform, fastest, random place inside the bounds, skyline / viewpoint terrain sampling, flight candidates; crash guards: no read of removed entities, alive, map bounds; round 3: flight candidates per ticked subject, river = narrow water, none found adds nothing; round 6: nearby (octree constructions, running vehicles, persons inside the radius only; moving subjects re-read, gone = nil; a failing octree query) |
| `tests/square_photo_mode/test_place.lua` | round 6: pm_place: area radius, every slice once per round (shuffled; no round starts next to the last slice), place points inside the area, distances by area, pitch inside the range rows (both ends used), subjects about half the shots / each before repeats / never outside, non-finite subject |
| `tests/square_photo_mode/test_window.lua` | round 6: pm_window rendered on a fake builtin: every tab and the footer build, no layout carries an inline styleSheet, every spacing class has its rule, at most 14 rules, footer controls, Tour tab per mode (This place, Wander; the renamed angle / distance rows); round 7: every Button, ToggleButton, CheckBox and every ToggleButtonGroup option of every tab and Tour mode has a tooltip; round 8: content and footer padded by Components (none on the `sqpm-content` layout), every Button outlined (`secondary` / `primary`) and compact, no inline sheet on a Button, three cells fit a row, the cell counts per tab, the Mode dropdown (items, tooltips, values, an unknown value ignored), dropdown items in the tooltip audit; round 9: no camera mode option on the Tour tab |
| `tests/square_photo_mode/test_shots.lua` | pm_shots: scores, closest pair (grid bins, cell borders), densest cell + main axis, skyline / viewpoint picks, every framing finite and facing as intended (eye position checks) |
| `tests/square_photo_mode/test_variety.lua` | round 17: pm_variety bags (20 clicks on a one-item pool give 20 distinct views, a five-item pool visits all before repeating, POOL_MAX, shuffle bag), vary / same / distinct |
| `tests/square_photo_mode/test_flight.lua` | pm_flight: ramps (C1), hop velocity continuity at both glide ends with the drift, no-drift glide at rest, drift ramp-in window, drift pitch bounds, path heading smoothness, waypoints inside the inner bounds, drone view; round 7: Ken Burns main moves / pace / pedestal, solveEye on bumpy ground (the eye exact and smooth while the centre's ground jumps; the old placement bobbed; height reads), the clearance lift before a hill, the zoom-limit / map-edge cap, NaN, Wander (x and y, in and out, slow, eased look); round 9: the camera model against the session's 12 eye checks (rms < 0.01, a constant offset 4x worse), inverse, centre lift / water, elevView / gameView, resSample / resUpdate (smooth, clamped, terrain-frequency noise filtered), solveEye exact under the model, the smoothness metric, replays on a synthetic game a little off the model over bumpy terrain: Wander at three angle ranges and a tour glide + Ken Burns hold as smooth as the plan (and round 8's way 4x / 1.5x rougher) |
| `tests/square_photo_mode/test_light.lua` | pm_light: sun times (golden hour by season, polar fallback), wrapping, override, restore plan (the player's changes kept, midnight), marker round trip / corrupt; pm_sky on a fake api: preset order of calls, restore order, player's cycle kept, unreadable cycle never switched, freeze / unfreeze / the player's unpause, a save repaired on load |
| `tests/square_photo_mode/test_hud.lua` | pm_hud on a fake api: hide / restore labels (exact filter back, absent stays absent, a changed filter kept), selector refresh, pause menu, a save made while hidden, Hide UI (stays hidden through time / camera / mouse, back on the pause menu, untick, new game), the tour's hidden UI (no timer, back when the tour ends); round 6: labels and hover kept prevented until shown, camera mode for a tour (pushed, probed on / fallback popped + hidden UI, kept for the session, Esc = left, pause menu / start pop), no tool = hidden UI, camera mode off = hidden UI, the footer's camera mode (Esc noticed; no tool = Hide UI), labels during tours; round 9: a tour never pushes the free camera; hover off during automated moves (re-asserted, back at the end, kept off by the labels, labels shown mid-move, pause menu, start) |

## Design (proven mechanics, reused from the DEV probe)

All from `mods/square_photo_quality_probe` (verified in game; `plans/square_photo_quality_probe/TESTING.md`).

- **Switching** (`docs/findings/map-camera.md` "Graphics settings from a mod: api.util.setAppConfig"): copy
  `api.type.AppConfig.new(api.util.getAppConfig())`, set the keys by name, `api.util.setAppConfig(cfg, false)`.
  The boost is never saved; `shadowQuality`, `geometryQuality`, `terrainQuality` and `grassQuality` are never
  written. Switching on runs in 6 stages (the safe 3, then geometry, terrain, grass one key each; round 19 after
  the DEV risky test 2026-10-14_2019_r18-test-risky) ("Highest graphics: the staged switch" below); the
  restore runs in the same stages reversed (the pause menu's restore stays one call; "Rev 1 feedback round 2" 2). A switch stalls ~1.2 s (texture reload): expected, in the tooltip and description.
- **Snapshot** = a plain table of the 9 graphics keys only (`pm_core.KEYS`: no shadows; geometry, terrain and grass since round 19, each its own stage). Restore = copy of the CURRENT config + the snapshot's
  keys, then `setAppConfig` + `saveAppConfig`. Never the whole old AppConfig: it holds other mods'
  `mainMenuState` prefs, audio and keys that may change meanwhile.
- **Marker** (the game, or any mod's `saveAppConfig`, may save the AppConfig at any moment while boosted): before
  boosting, `{ boosted = true, orig = snapshot }` goes into `AppConfig.mainMenuState["square_photo_mode"]` (copy
  of the table, our key set) and is saved while the graphics are still the player's own. Restore clears it.
- **Safety net**: on the first frame of each game (plugin `onStep`, once per mount), a marker restores the keys
  still at their boosted value and keeps keys the player changed since (`pm_core.recoverKeys`), then is cleared.
  Covers a crash or kill; untested in game (the probe's C2 run was skipped, `findings/gui.md`: Force Quit and
  Steam stop open the pause menu too).
- **Exit**: quitting runs no `react.onUnmount` (`docs/findings/gui.md` "Quitting runs no react.onUnmount").
  `react.onEvent("openPauseMenu", fn)` fires on Esc, the menu button, Cmd+Q, Force Quit and Steam stop, always
  before Quit / Settings can be reached: the camera moves stop and the highest graphics go off there, at once
  (not in the next frame); the toggle shows off afterwards, the window stays as it is. Expected behaviour.
- **Failure handling**: every api call in pcall. A failed boost after the marker was saved puts the snapshot back
  at once; a failed restore leaves the marker, so the next load repairs it.
- Threads: everything on the GUI Main Thread (plugin `onStep`, button callbacks, `onEvent`). Never touches the
  simulation; the only savegame data is the rev 2 saved views (GUI save data; severity None / None, cosmetic).
- Log lines: `[PhotoMode] start: ...`, `hq on: 3 stages, 3 frames apart`, `hq on: player's settings ...`,
  `hq on: marker ms= saved=true`, `hq stage N/3 keys=a,b ms=` (or `keys=- (already highest)`), `hq on: 3 stages
  ms=<sum> now ...`, `hq off(toggle|pause menu|stale) after stage K of 3 ms= saved=true now ...`, `hq on
  cancelled (<why>) before stage 1`, `hq undo ...`, `window closed (button)` / `window closed by the player`,
  `marker found: restoring ... | kept (not at the highest) ...`, `... ERROR ...`.

## UI

House style (`plans/ui_style/PLAN.md`): base `builtin.ToggleButton`, white 24 px camera icon, no inline colour
on tile or icon, pressed while the window is open (synced every frame from the module state). While the highest
graphics are on (window open or closed) the button's contour is the base `Ok` green (inline `borderColor`, as
Supply Gaps shows its overlay; the icon can't be tinted without overriding the base states) and the tooltip
gets the line "Highest graphics: on.". Always the icon: **Photo Mode is an exception to CLAUDE.md's
`hudButtonStyle` convention** by the user's request (2026-10-14: no mod settings other than the debug one), so
mod.json has only `sqperf_log`; the Text style (a plain "Photo" / "Photo: HQ" button) is gone. A value of the
old param left in a player's settings is never read. "Photo" / "Photo: HQ" remain only as the plain button
that stands in when the icon button's render fails.

The "High graphics mode" checkbox (base CheckBox, as Industry Flows and Problem Radar's settings) sits in the
window's Settings tab (round 12; before that the footer), next to the "Hide labels and hover" checkbox (checked while on
or staging; shows unchecked at once when unticked). Its tooltip names the ~1 s stall, that it stays on when the
window closes, and that the settings come back when it is unticked or the menu opens. (Rev 1 had a
"Highest graphics" ToggleButton above the tabs; the user asked for a checkbox at the bottom, 2026-10-13.)
Padding 8 px around the 24 px icon (a 40 px tile, like the layers button and our other top-bar buttons;
CLAUDE.md, `plans/ui_style/PLAN.md`).

Layer window offset: the stylesheet carries the shared block with `square_photo_mode` appended LAST to
`SQ_RIDGE_MODS`, so it adds the 4 rules only when none of the five other top-bar mods is active. Each mod reads
only the entries before itself, so the other five need no change (`plans/ui_style/PLAN.md`).

## Performance

Audit 2026-10-12 (offline, nothing run in game yet). What runs when:

- **Every frame, window closed and no switch running**: the plugin's onStep compares Lua values (started,
  button states shown, `S.offRequest`, `S.hq`, window wanted / open, `driver.busy()`); no react, api or clock
  call, also while the highest graphics are on. The window is closed, so its onStep doesn't exist. Exception:
  for a few frames after a follow was let go (window closed included), the driver
  checks `getFollowEntity` once a frame (at most ~9 frames, "Rev 1 feedback" 3).
- **Every frame, window open and idle** (no orbit / tour / glide, or in the cockpit): the driver's step returns before any
  api call or clock read; SQPERF times it (two Clock reads, ~0.3 µs). The window's onStep compares a number
  (the sum of three change counters) and sets its react state only when it moved: one render per change.
- **Every frame during orbit / glide / tour (glide and hold drift)**: one getCameraData, one setCameraData (a new Vec5f each frame:
  reusing one by writing its fields is untested), getFollowEntity while following, `cam.userMoved`. Views are
  read and computed into two scratch tables (`cam.lerpView` / `cam.orbitStep` take an `out` table), so no Lua
  table per frame. No log line per frame: a failing setCameraData stops the moves with one line.
- **Per click / per tour hop** (never per frame): `pm_world.pick`. Lists cached (vehicles 5 s, persons 10 s,
  stations / towns / industries 30 s) as the engine returns them (no copy). Random picks read each tried
  entity's position once. The scans (longest, bridge, airport) stop at **35 ms from the start of the click**,
  list build included (api.type.Clock), so a click is one hitch below ~50 ms; each continues where its last
  click stopped, and "longest" re-scores its best train first, so repeated clicks cover a big fleet.
- **On change only**: `setGuiSaveData` (add / delete a view), `getGuiSaveData` once per game.
- **The switch** (~1.2 s texture reload, now spread over 3 stages each way) is expected and logged per stage
  with its `ms=`. Measured: the texture stage is the whole stall (911-1095 ms), every other stage 0.2-33 ms.
- **Round 2 additions**: a tour hop computes its view from pm_flight into module scratch tables (no Lua table per
  frame); a flight frame adds two `getHeightAt` and a Catmull-Rom evaluation (no allocation); a flight's next
  waypoint (one candidate list: towns, ~12 stations, ~6 industries, 10 random points with `isOnWater`) about once
  a minute. The photographer's shots are one budgeted scan per click (35 ms from the click, as before; the
  winner's framing reads a few components more: position, track edge, nodes), skyline / viewpoint ~16-100
  `getHeightAt` per click. "Hide labels" writes the base GUI save data once per tick / untick. Hide UI has no
  timer and no mouse / camera check (since round 4 one game-speed read a frame while hidden: below). With the
  window closed and nothing hidden nothing of this runs.
- **Round 4 additions**: a flight frame adds the flight-input compare (Lua only) and the look offset (no
  allocation); the horizon look adds nothing per frame (one tangent from the same path evaluation). While the UI
  root is hidden (Hide UI or a tour's hidden UI) the escape hatch reads `GAME_SPEED` once a frame (one
  `getComponent`, as the base GameSpeedHelper every frame); while frozen, the same read once a frame. The Light
  tab reads the state (GAME_TIME, the game script state, the environment) only when it renders; its buttons send
  one to five commands per click. Horizon shots: two `getHeightAt` per click.

- **Round 6 additions**: a flight leg looks up its candidates once at its start (`world.flightCandidates`) and plans
  all its waypoints then (at most 12; was a lookup whenever the path ran short, about once a minute mid-flight);
  the frames only evaluate the spline. "This place": `world.nearby` at the tour start and every 6 hops (an octree
  circle query for constructions, a 15 ms budgeted walk of the cached vehicle list, 150 random persons' positions),
  per hop one position read of a moving target; nothing per frame. Camera mode: while probing, two `getEye` /
  `getCenter` reads a frame (2 frames); while on, one `getActiveTool` a frame (a Lua table read in the tool stack);
  the footer's camera mode the same until the player leaves it. Labels and hover hidden: nothing per frame (the
  selector stays prevented; no allow a frame later any more). "Hide labels during tours" (default on) means fewer
  HUD icons to lay out and draw while the tour runs; camera mode hides the whole game GUI (its layout work stops
  too). Ideas not built: a lower HUD icon render distance during tours (no API), fewer persons / vehicles drawn (no
  API), the high graphics mode off during tours (the player's choice).

- **Round 7 additions**: every frame of a glide, Ken Burns hold, flight or wander runs the eye-space solver
  (`pm_flight.solveEye`): 1 `getHeightAt` for the clearance ahead of the eye + usually 3 along the look ray
  (fewer once exact, up to 6 in the frame a crest stops hiding the ground behind it), so 3-7 a frame; a flight
  1-2 more (the ground ahead of the eye for its altitude, the look point). `pm_world.groundAt` calls a module
  function through pcall (no closure per call); each call still makes one `Vec2f`. No Lua table per frame: the
  pose is plain numbers, views go into scratch tables. Per hop: one `getHeightAt` for the arrival's reference
  ground (and one for the start when it is the current view); per wander look target (every 10 s): one
  `getHeightAt`, at most one position read; per wander start: `world.nearby` (as This place). "eye check": one
  `getEye` per hop arrival / flight / wander target, at most 3 per move. Measured offline only; TESTING.md R10.

- **Round 8 additions**: every frame of an eye-space move adds `getEye` + `getCenter` (the pitch offset sample,
  pcall on the api function itself, no closure; numbers only, no Lua table). The `cam trace` (first 40 frames of
  the session's first two moves, or of every move with the debug log on) adds a log line, `getHeightAboveTerrain`,
  `world2Screen` and `getSize` in those frames only. The saved-views pick reads the cached list (no save-data
  read). Measured offline only; TESTING.md U11.

- **Round 9 additions**: per frame of an eye-space move the same `getEye` + `getCenter` (now the model's residual
  and the smoothness metric: numbers only), the camera model (a few `sqrt` / `sin`), and `getHeightAt`: usually 4
  (1 clearance + 3 on the look ray, offline mean 3.3-3.6 over the Wander replays), + 1 while a jump of the look's
  meeting point is blended (0.5 s after a crest), and in a rare frame a second search (a look flatter than the
  game can show there): at most 2 + 2 x 6 = 14. The hud's `step` runs each frame of an automated move (a counter;
  `preventReactSelector` fired at its start and 2 and 30 frames later). Wander traces: 45 log lines in its first
  10 s, 5 more at 30 s and 60 s. Measured offline only; TESTING.md V9.

SQPERF (`pm_perf.lua`, like the other square GUI mods with per-frame work): `perf` (ctx gui, slow above 60 ms):
`pick_<kind>`, `list_<key>`, `window_render`, `tour_advance` (each hop / flight start incl. its pick or scan),
`tour_flight_start`, `place_subjects` (round 6); `perfStep` (ctx step, 16 ms): `camera_step`, only while the window is open.
mod.json param `sqperf_log` ("Debug: performance log", Off / On). Logs: `[SQPERF] mod=square_photo_mode ...`;
`make perf ARGS='--mod square_photo_mode'`.

## Crash safety

Offline audit 2026-10-12 against every crash class in `docs/findings/` and the archived crash logs (nothing run in
game yet; in-game checks: TESTING.md C1-C11). What guards what:

- **Threads**: every api call runs on the Main Thread (plugin onStep, onEvent, button callbacks, window render /
  onStep). No onStepTimer, no hudIconScript, so no GUI-thread-only call can land on a worker thread.
- **Render errors** take the UI down: the top-bar button is built in pcall (a plain text button stands in,
  `button render ERROR` once); each window tab is built in pcall (`tab <key> render ERROR`, one grey line);
  formatted labels go through `pm_core.fmt` (never raises on a translation whose placeholders don't fit); the
  status line shows only a non-empty string. Recipe roots are BoxLayouts, Component layouts plain BoxLayouts,
  the saved views' ScrollArea content a `builtin.Component` (findings gui.md), the rename field the base
  `gui_react_util.FocusTextInputField` (as the line manager), no `mouseTransparent`, every builtin field checked
  against `builtin.d.tl`.
- **Entity lifetime**: `getComponent` wants an existing entity (`api/engine.d.tl:1686-1690`); the cached lists are up
  to 30 s old, so `pm_world` checks `entityExists` before every component read. `followEntity` and
  `enterFollowCameraCockpit` run only after `pm_world.alive(subject)` right before the call: exists, still a vehicle
  (TRANSPORT_VEHICLE, not in a depot) or a person (ids are reused after a removal). When the game ends our
  cockpit itself (`stoppedFollowAction`), the driver calls `leaveFollowCameraCockpit` as the base FreeCamTool does.
- **Camera values**: every `setCameraData` goes through `pm_cam.safeView`: a NaN / inf field is never sent (one log
  line, moves stop); distance 1-20000 m, pitch 0 to just under straight down, centre inside the terrain's
  bounding box (`getBoundingBox`, read once per session; ±1e6 m without it), angle wrapped, no -0. `clamp`,
  `wrapAngle` and `orbitStep` turn NaN / dt 0 into no motion. Saved views are checked the same way before saving.
- **Settings switch**: a gate (`pm_core.newGate`) lets one setAppConfig (a stage or the restore) run at a time;
  an off asked for meanwhile (the pause menu inside a stage's stall) runs right after it, and no further stage
  follows. The toggle's on and off are requests the onStep carries out; a second click before the off ran
  cancels the off. The marker is written only on a complete copy of
  `mainMenuState` (a partial one would wipe other mods' prefs); marker values read back are validated per key
  (`pm_core.validValue`: levels 0-2, MSAA 1/2/4/8/16, SSAO boolean, scale 0.5-1.0), broken ones are not restored.
  A failed boost puts the snapshot back; a failed restore leaves the marker for the next load.
- **Save data**: saved views are GUI save data only (`pm_cam.readBookmarks` drops anything malformed and repeated
  ids, at most 50; names through `pm_cam.cleanName`: ASCII control characters to spaces, trimmed, at most 40
  characters cut on a UTF-8 character boundary, byte by byte because `%c` / `%s` follow the C locale).
  Severity None / None: nothing in the simulation needs the mod (to confirm: P11).
- **Expired react states**: `:set()` only after `hasExpired()` (plugin and window).
- **Follow release**: three different camera calls (`focusPosition`, `setManualCamera`,
  `leaveFollowCameraCockpit`), each in pcall, each followed by a `safeView`-checked `setCameraData`; at most one
  call per 3 frames, given up after the third. A new follow cancels a release in progress.
- **Switch frames**: no window opens or closes in a frame with a setAppConfig of ours: the onStep does either
  a stage / the toggle's restore or the window's open / close, and a stage (or the toggle's restore) waits a
  frame after any window open / close, the player's X included. The pause-menu restore is the exception: it
  runs in the event (a quit may follow), and Esc may close the top window through its onClose in that frame
  (closing then restoring in one callback worked 3 of 3). Why: "Highest graphics: the staged switch" below.
- **Round 2 guards**: the HUD filter is written as the base window writes it (a deep copy of the base GUI save
  data, only `hudFilter` changed), never hides `BASE_NODE` (no toggle to undo it), and goes back only while it
  still is our hidden filter (a filter the player changed meanwhile stays); our save data keeps the player's
  filter, so a save made while hidden (autosave) is repaired on the next load. "allowReactSelector" always
  follows "preventReactSelector" (next frame, the pause menu, a new game), so the map selector is never left
  off. The UI root is shown on every exit (Hide UI: the pause menu, unticking, a new game; a tour's end, the same for a tour's hidden UI; no timer). Every framing, flight and drift view goes
  through `safeView`; framings are clamped by `clearPitch` over the terrain; flight waypoints stay inside the map
  (12 % inset). The look offset is measured, never guessed per shot.
- **Round 4 guards**: every look offset and horizon view goes through `safeView`; horizon distances stay within
  `cam.ZOOM_LIMIT` (4000 m) and their centres inside the map; `flightInput` / `lookStep` ignore NaN. The Light
  tab: every call in pcall, values normalised (`pm_light.change`: time wrapped to whole seconds as the command
  wants, clouds 0-1, day 1-365, sun wrapped), marker values validated (`pm_light.validState`), a cycle that
  can't be read is never switched (it could not be put back), only values still ours are restored. The escape
  hatch only shows UI (and stops the tour); it never sends a command.
- **Round 6 guards**: camera mode pushes and pops the base FreeCamTool only through the tool stack API, in pcall;
  a pop of a tool not on the stack does nothing, so every exit pops (tour end, pause menu, fallback) and Esc's own
  pop is harmless. The UI is never left hidden: in camera mode the game hides and shows it; the fallback hides the
  root ourselves with the existing escape hatch (pause key), pause menu and game-start restores; a failed push goes
  to the hidden-UI path. The probe never sends a camera call of its own (it reads the tour's own views back);
  "left" only after 5 frames on (a push lands through a react state). `pm_place` views are finite and inside the
  area, distances within `cam.SAFE` / `MAX_DIST`, every view through `safeView` and `clear` (terrain). Nearby
  subjects: `entityExists` before every read (`pm_world.comp`), a moving one re-read per hop and skipped once gone
  or out of the area; the octree query in pcall. Labels and hover: `allowReactSelector` on untick, pause menu,
  tour end (labels hidden for the tour), never left prevented past those. The tour's pause unfreezes only a freeze
  it started itself.
- **Render-buffer settings**: `shadowQuality`, `geometryQuality`, `terrainQuality` and `grassQuality` are in no
  stage, not in `BOOST` or `KEYS`, so neither the switch, the restores nor the safety net write them (tests:
  test_core "no stage ever touches geometry, terrain, grass or shadows", "an old marker with geometry / terrain /
  grass / shadows restores none of them"; test_button "safety net: an old marker holding ...", "toggle on and off
  never changes shadows, geometry, terrain or grass").
- **Stylesheet budget**: Photo Mode adds 8 rules, 12 when it is the only top-bar mod (the shared 4 layer-window
  rules are added once for all six; round 6 added the 3 spacing classes, `tests/square_photo_mode/test_window.lua`
  checks the total). The total of all active mods must stay below ~200 (findings scripting.md).
- **Not guarded, needs the game** (TESTING.md C4, C5): our buttons while a build tool, the game's free camera or
  the game's own cockpit is active. The API has no getter for those states.

## Rev 2: a real photo mode (4 phases)

Each phase stays read-only toward the simulation (except Phase 3's freeze, which only pauses) and restores
everything it changes when photo mode turns off or the pause menu opens. Ships as rev 1 (nothing uploaded yet).

1. **Camera window + subjects** (built 2026-10-12; first run 2026-10-13, feedback built: "Rev 1 feedback"). Below.
2. **Shutter + Hide UI** (probe answers: `docs/findings/map-camera.md` "Screenshots" and "Hiding the game UI",
   session `2026-10-13_0339_sqpq`).
   - *Shutter* (built 2026-10-13, untested: TESTING.md X1-X8). `api.gui.camera.takeScreenshot(scale)` multiplies
     the viewport size: scale 4 works (10240x5760 at 2560x1440, an 89 MB PNG, ~9 s stall while it encodes). A shot
     never contains the UI, so the shutter needs no hide-UI step of its own. The first request of a game session
     writes no file, and a request right after a big shot is dropped too. As built:
     - **Where**: the window footer (every tab), a row under the checkboxes / Smooth camera / Free camera row and
       above the status line: the label "Screenshot" and three compact outlined buttons "1x", "2x", "4x"
       (`pm_window.lua` `shutterRow`, the existing `flow` / `button` helpers and classes, no new CSS rule).
     - **Tooltips** (`shutterTip`): the output size in pixels, read at render time from
       `api.gui.camera.getSize()` ("Width and height of the viewport, in pixels", `api/tealdef/api/gui.d.tl:499`,
       pcall; it already feeds the round 8 `cam trace` `scr=` values, which come out right), times the scale
       ("Saves the view at 5120 x 2880 pixels, twice your screen's width and height."); without a size, the size
       in words. Every tooltip: the file goes to the game's screenshots folder, the interface is never in the
       picture; 2x: the game pauses for a moment; 4x: it stalls several seconds and the file is large (~90 MB at
       2560 x 1440). Whether getSize is in physical pixels on a Retina Mac (the file's size) is X1.
     - **Timing** (`pm_shutter.lua`, pure, `tests/square_photo_mode/test_shutter.lua`): the first press of a
       session (a Lua state: one per loaded game) sends a scale-1 primer and the real shot `PRIMER_MS` = 1000 ms
       later from the driver's step (no blocking wait; `D.busy` keeps the step running with the window closed).
       After each shot the shutter is busy for `COOLDOWN_MS` 1x 2 s, 2x 4 s, 4x 12 s, counted from the first
       step after the request (a 4x stall delays that step, so the cooldown runs after the stall). While busy the
       three buttons are disabled and a press is ignored with a status. A failed call (pcall) leaves the shutter
       usable, no cooldown; a failed primer is tried again next press. `D.stopAll` keeps the primed state.
     - **Statuses** (driver.S.status, the window re-renders on its version): "Taking the screenshot..." (primer
       sent for a 1x), round 11: "Saving the 2x / 4x screenshot: the game freezes for ..." (a 2x / 4x press,
       shown ANNOUNCE_MS before the blocking call; also for its primer), "The screenshot is in the game's
       screenshots folder." (the call returned: it blocks until the file is written; again when the cooldown is
       over), "Wait a moment: the last screenshot is still being saved.", "The screenshot could not be taken.".
     - **Log**: `screenshot primer scale=1 (first of the session), scale=N follows`, `screenshot scale=N
       viewport=WxH out=WxH call ms=N` (or `viewport=?`; round 11: the call's blocking time), `screenshot scale=N
       announced ...`, `screenshot cooldown over`, `screenshot scale=N ERROR ...`.
   - *Hide UI*: built in the round 2 feedback (window footer; back after 10 s, on camera input, on mouse
     movement over the map after a 0.6 s grace, on the pause menu; whether Esc reaches the game while the UI root
     is hidden is TESTING.md G3c); since replaced in the footer by "Camera mode" (round 6), now "Free camera" and
     "Smooth camera" (round 10). Original plan:
     *Hide UI* button in the Photo Mode window: hides the game HUD and our own window, to frame and look at the
     picture (or record a video) without any UI. `api.gui.byId.setVisible("react.game-ui-root", false)` holds
     until set back (`setVisibilityByClass` is undone by the game within ~1 s; `toggleFreeCamera` also hides it,
     but only `leaveFollowCameraCockpit` brings it back). The plugin's `react.onStep` keeps running while hidden,
     so getting the UI back never needs a visible UI: Esc (the pause-menu restore, which already turns photo mode
     off), a timer (e.g. 10 s), and the next click or key press (to check in game: whether a click or key while
     hidden reaches our onStep, e.g. a mouse-state read or an input action). Paired with the shutter: "Hide UI"
     then "Shot" (or one "Hide UI, shoot, show" button: hide, wait 2 frames, shoot, show) lets the player see
     the clean frame, take it and get the UI back. Restored on every exit path (window closed, pause menu, a new
     game), as the graphics.
   - Dropped: the rule-of-thirds grid. A full-screen overlay Window wrapper crashed the game
     (`docs/findings/map-camera.md` "Full-screen overlay window crashed"); the user is fine without a grid.
3. **Light & weather** (built 2026-10-13, untested: "Phase 3: Light & weather" below, TESTING.md L1-L9). Original
   plan: time-of-day buttons (golden hour, blue hour, noon, night; `api.cmd.makeGameSetTimeOfDayCmd`),
   live sliders for cloud cover / rain, day of year (season) and sun rotation via
   `api.gui.rendering.getEnvironment()` / `setEnvironment(e)` (base precedent
   `.cache/game/base/content/mission/tasks/utility/clouds.tl`), freeze (pause the simulation); all restored on
   exit.
4. **Looks** (built 2026-10-13, untested: `LOOKS.md`, TESTING.md K1-K13). Probe T7 (`2026-10-13_1924_sqpq`,
   `docs/findings/environment.md`): a mod's `.env.lua` is registered and switchable at runtime. Built
   **rendering only** (`api.gui.rendering.setEnvironment(environmentRep.get(id))`, the six live atmosphere values
   put back after each switch); never `api.gui.game.setEnvironment`, which would persist our env into the save.
   Eight looks (Hazy morning, Crisp & clear, Misty valley, Mirror water, Stormy sea, Moonlit night, Dramatic,
   Storybook) per base climate, generated by `tools/gen_photo_looks.py`; plus weather over time, time-lapse,
   seasons and sun placement. Restored on "Original look", the pause menu and the next game start; the window
   close keeps it. Unknown climates get no looks (a note instead). Original plan: a row of look presets (Golden
   hour, Misty morning, Storm, Toy model, Night city).

### Phase 1: the Photo Mode window (built, first run 2026-10-13)

Coupling (since 2026-10-13, "Highest graphics: the staged switch"): the button opens / closes the window and
stays pressed while it is open; closing it (button or X) stops every camera move (`pm_driver.stopAll`); the
pause menu stops them too. The graphics have their own toggle in the window and don't follow the window.

Window (`pm_window.lua`): base Window (id `squarephotomode.window`, left edge a fifth down, 420 px content),
base TabWidget with three tabs, `font-scale-headline` headings, FlowLayout rows of base Buttons / ToggleButtons
(each item carries its 4 px gap), a status line under the tabs (body font, its own padded box, wraps at 400 px)
for "nothing found" texts.

- **Subjects** tab. *Random subject*: Anything (a weighted random kind among those that exist), Vehicle, Train, Road vehicle (bus, truck, tram), Aircraft, Ship, Person,
  Station, Town, Industry. *Interesting*: Busiest station (most line stops: `lineSystem.getStationGroup2LineStopsMap`),
  Biggest town (population `getTown2personCapacitiesMap()[town][1]`), Longest train (most parts in
  `transportVehicleConfig.vehicles`), Vehicle on a bridge (the MOVE_PATH edge under the vehicle is a BRIDGE
  BASE_EDGE), Aircraft at an airport (flightState TakeOff / Landing, else Approach / Taxi). The scans read one
  component per vehicle within 35 ms of the click (list build included), each going on where its last click
  stopped (the first from a random start), and log their coverage (`scan ...: read N of M`).
- **Camera** tab. *Shot* around the current centre (angle kept): Eye level 25 m / 0.04 rad, Low angle 60 m /
  0.12, Drone 350 m / 0.60, Bird's eye 900 m / 1.45. *Camera moves*: Orbit (toggle, a turn a minute, keeps the
  player's zoom; works while following), Follow (`followEntity(last vehicle / person, false)`; off = the staged
  release, "Rev 1 feedback" 3), Cockpit (`enterFollowCameraCockpit(last vehicle)`; leave: button, window closed, pause
  menu, or the game's own `stoppedFollowAction` event).
- **Views** tab. *Saved views*: Save view (disabled at 50), then one row per view: name (default "View N",
  pencil = rename in place), Go, move up / down (base mod-selector icons), delete (trash); more than 8 rows
  scroll (300 px). *Tour* (moved to its own tab in round 2, which also added modes, range, places and the
  photographer's shots: "Rev 1 feedback round 2"): Start / Stop, source Random subjects / Saved views, 5 / 10 /
  20 s (default 10) at each place. Random subjects cycle `pm_cam.TOUR_KINDS`, skipping kinds with nothing (and
  flying aircraft); saved views play in list order and loop. A 4.5 s glide to each place (smoothstep, distance log-interpolated, a rise of a third of the ground
  distance capped at 3500 m), then the hold drift.

Framing (`pm_cam.FRAMING`, distance / pitch, random angle): person 22 m, road 40, tram 45, train 120, aircraft /
ship 150, station 250, industry 350, town 900; pitch 0.26-0.52 rad (15-30 degrees). A flying aircraft (more
than 40 m above the terrain under it) is followed (`followEntity(e, true)`) instead: a ground-centred view
can't reach its height.

Positions (`pm_world.lua`): BOUNDING_VOLUME centre (base `scripts/entity_util.tl`), a vehicle without one its
middle carriage's (base `mission/mission_task_util.tl:123-145`), a person `MODEL_PERSON.position`, a station
group its first station's construction, a town `makeMapFromGame(false, true, false, false)` (as Stress Test).
Lists cached 5 s (vehicles), 10 s (persons), 30 s (stations, towns, industries); `[PhotoMode] list <kind> n= ms=`.
Random picks try up to 60 random slots (vehicles in a depot skipped); own LCG (`pm_cam.newRng`), never
`math.randomseed` (shared Lua state).

"Player moved the camera" (`pm_cam.userMoved`): after each of our `setCameraData` calls, the next frame's
`getCameraData` differing by more than 5 m / 3 % distance / 0.03 rad angle or pitch stops orbit and tour
(centre ignored while following). Untested assumption: `getCameraData` reads back exactly what we set (the
zoom finding saw that for distances inside the limit).

Bookmarks: `api.gui.game.setGuiSaveData("square_photo_mode", { v = 1, views = {...} })`, read once per game with
`getGuiSaveData`, malformed data dropped (`pm_cam.readBookmarks`). GUI data of the savegame only (base
`layer_hud_filter.tl` writes its own key the same way); severity stays None / None (to confirm: P11).

Skipped, with reason:
- **Dutch angle**: `setCameraData` takes x, y, distance, angle, pitch; there is no roll.
- **Newest construction**: entity ids are reused after a bulldoze and no component carries a build date, so
  "newest" can't be told cheaply.
- **Free camera toggle**: the game bar already has it, and the API has no getter for its state
  (`toggleFreeCamera` only flips), so photo mode off couldn't reliably put it back.
- **Busiest by passengers**: waiting counts need per-terminal calls per station
  (`simPersonSystem.getSimPersonsAtTerminalForTransportNetwork`); line stops are one map call.

Log lines: `[PhotoMode] window closed (button)`, `jump <kind> (<why>) entity= kind= view=x,y,d,a,p` (Anything: `jump any (any <kind>) ...`), `...
airborne: follow`, `jump <kind>: none`, `shot <key> view=`, `orbit on|off (<why>)`, `follow on|off (<why>)
followEntity=<id>`, `follow released by focusPosition|setManualCamera|leaveFollowCameraCockpit (<why>)`, `follow
still on after every release call (<why>)`, `follow release <call> ERROR`, `cockpit on|off`, `stoppedFollowAction:
...`, `tour on source=random|views every=Ns`, `tour <kind> (<why>) entity= to=` / `tour view <id> to=`, `tour off
(camera moved: pan|zoom|turn|tilt | button | no saved views | ...)`, `bookmark add|delete|move|rename id=`, `bookmarks loaded n=`, `window closed by the player`, `scan longest|bridge|airport:
read N of M ms=`, `busiest station <id> lineStops=`, `biggest town <id> population=`, `... ERROR ...`.

## Rev 1 feedback (first in-game run 2026-10-13, built in code 2026-10-13, untested: TESTING.md F1-F10)

Session `2026-10-13_0325_session`. Every item below keeps the Performance and Crash safety guarantees above.

1. **Fast feel on open, safe order** (revised 2026-10-13 after a crash; superseded the same day by "Highest
   graphics: the staged switch" below after a second crash): the click only sets the top-bar
   button pressed (react state; the text button shows "Photo: on"), no window and no other GUI is built; the
   plugin's onStep runs the switch (marker, then boost, behind the gate) 2 frames later (`ON_DELAY_FRAMES`), so
   the pressed button is drawn before the ~1-2 s stall, and opens the window right after the boost in the same
   call, as in the first run's order (worked 3 of 3, `2026-10-13_0325_session`). A second click or the pause
   menu before the switch cancels it (nothing changed yet). No switch notice in the window (it is opened after
   the switch). Why: the first build of this item opened the window with a "Switching..." notice and switched
   3 frames later; its first use crashed natively 0.1 s after the boost (render thread, MoltenVK
   `mvkCmdBeginRenderPass`, 3x `Could not invert matrix` first; `2026-10-13_0342_sqot`). Cause unproven;
   findings map-camera.md "Graphics settings from a mod". Off keeps the order that worked: camera moves
   stopped, window closed, then the restore. Offline: `tests/square_photo_mode/test_button.lua`.
2. **Status line**: was `font-scale-annotation` with a CSS `maxSize`, squeezed onto the window's bottom edge
   (screenshot). Now `font-scale-body` in its own box (padding 8 top, 4 a side), wrapping with a fixed width
   (`size = { 400, -1 }` + `textAutoWrap`, as Better Minimap's hints), inside the content, so the window grows
   with it.
3. **Follow release**: `follow off (button)` logged but the camera kept following until the player moved it:
   `setCameraData` does not end a follow. The base game has no Lua unfollow: every base `followEntity` caller
   leaves the follow to the player's input, and the C++ FollowAction "fires this event to tell us when it closed
   itself" (`stoppedFollowAction`, `gui/main/free_cam_options.tl:25-28`). Chosen: a staged release checked with
   `getFollowEntity` 3 frames after each call: 1 `focusPosition(centre with ground height, distance)` (sets a new
   camera target; base `line_warning.script.tl:194`), 2 `setManualCamera(centre, distance)` (base
   `mission_framework_react_util.tl:228`), 3 `leaveFollowCameraCockpit()` (ends the free camera, findings
   map-camera.md "Hiding the game UI"; safe with no cockpit, the base FreeCamTool's pop). After each call the
   kept view is set again (neither call changes distance or angle). The log names the call that worked; if none
   did, a status line asks the player to move the camera. Jump, Go to a view and the tour release a follow the
   same way. Not used: `followEntity` with an invalid id (an engine assert pcall can't catch is possible).
   Unverified which stage works: F3 settles it; then drop the stages that don't and add a finding.
4. **Anything**: first button of the subject list; `pm_cam.weightedOrder(ANY_KINDS)` (train 3, road 3, ship
   1.5, aircraft 1.5, station 2, town 2, industry 1.5, person 1) and the first kind with something wins.
5. **Saved views table**: rows as in "Views tab" above; cap 50 (save data: 50 x 7 fields, a few kB); names in
   the save data (`name`, absent = default "View <id>"), `cleanName` validation, `maxLength` 40 on the field.
6. **Tour source**: Random subjects / Saved views (in list order, looping; an empty list: not started, status
   "Save a view first, or tour random subjects."; a list emptied mid-tour stops it at the next hop).
7. **Tour motion**: glide 4.5 s (was 2), smoothstep, rise on long hops as before. Hold: Ken Burns drift
   (`pm_cam.kenBurnsParams` per hop from our LCG, `kenBurnsView` eased in and out over the hold): orbit 0.35-0.8
   degrees/s either way, pitch +-0.04 rad, centre pan sideways up to 15 % of the distance, zoom +-8 %; half of
   that around a saved view. Orbit on during a tour adds its turn to the drift. Every view through `safeView`.
8. **Tour framing** (random subjects): `pm_cam.tourFrame`: distance 25-90 m (geometric), pitch 0.04-0.20 rad,
   each kind at its own place in that range (person closest, town widest) +-15 % random. Saved views: the view
   itself is the target.
9. **modinfo summary** mentions the camera window (13 languages).

Also fixed from the log: `getEntitiesWithComponent(MODEL_PERSON)` raises "Cannot loop over this component type"
(every persons list build logged a traceback): tried once per Lua state, then SIM_PERSON directly (finding added:
`docs/findings/lines-vehicles.md`).

## Highest graphics: the staged switch (built 2026-10-13; worked 4 of 4 in `2026-10-13_0418_session`)

Since round 3 (2026-10-13) there is no shadow stage and since round 5 no geometry / terrain / grass stage: 3
stages, only keys that reload images / screen effects ("Rev 1 feedback round 3" 1, "Rev 1 feedback round 5"). The
table below shows the current 3 stages.

Why: the one-call switch (every key in one `setAppConfig`) crashed the game natively twice, in the renderer
(MoltenVK `mvkCmdBeginRenderPass`, after 3x WARNING "Could not invert matrix"): `2026-10-13_0342_sqot` (window
opened 3 frames before the switch) and `2026-10-13_0356_top-up-779299` (switch first, window right after it in
the same call; ~21 min into the session, another save loaded first). Both came after 13-21 min of play; ~20
earlier switches in fresh sessions worked, from the same starting settings. Cause unknown (findings
map-camera.md "Graphics settings from a mod"). The user asked for:

1. The button only opens / closes the window (pressed while open); no graphics change on open / close.
2. A "Highest graphics" toggle in the window (top, above the tabs) turns the boost on / off.
3. Closing the window keeps the boost on; the button shows it (green contour / "Photo: HQ" / tooltip line).
4. Restore: toggle off, pause menu (`openPauseMenu`, the safe point before any quit / save), the marker safety
   net on the next load. After the pause-menu restore the toggle shows off. Camera moves stop when the window
   closes.
5. The staged switch, to spread the renderer's work and to name the stage in the log should it crash again.
6. No window open / close in the same frame as any `setAppConfig` of ours.

Sequence (`pm_core.STAGES`, `STAGE_DELAY_FRAMES` = 3, both in pm_core.lua):

| Frame | Call |
|---|---|
| click | toggle shows on (`S.hq = "staging"`), nothing else |
| +3 | snapshot, marker `{ boosted, orig }` set and **saved**; stage 1 `textureQuality`, `terrainTextureQuality` |
| +6 | stage 2 `useSsao`, `ssrQuality` |
| +9 | stage 3 `numMSAASamples` (highest supported), `resolutionScale` 1.0; `S.hq = "on"` |

Each stage is its own `setAppConfig(cfg, false)` on a fresh copy of the current config, never saved, behind the
gate, logged `hq stage N/3 keys=... ms=`; keys already at their highest are left out and a stage with nothing to
change makes no call (the next one follows in the same frame). A stage due in a frame right after a window
open / close waits one frame. Off drops the remaining stages; the toggle's off (next onStep) then runs the
staged restore (since round 2: the stages reversed, `pm_core.RESTORE_STAGES`, marker cleared and saved with the
last), the pause menu (at once) and a new game (`stale`) restore the snapshot in one call (+ marker cleared,
saved), logged `hq off(<why>) after stage K of 3`. Off before stage 1 changes nothing (`hq on cancelled`). A failed stage restores at once (`hq undo`).
The logs named the stage: both staged crashes (`2026-10-13_0522`, `_0524`) came right after stage 4
(`shadowQuality`), so that stage was removed; the next (`2026-10-13_0558_session-crash`) right after stage 2
(`geometryQuality,terrainQuality,grassQuality`), so that one went too (round 5). If a crash returns, the last
`hq stage` line names the stage again.

## Rev 1 feedback round 2 (second in-game run 2026-10-13, built in code 2026-10-13, untested: TESTING.md G1-G10, S1-S12)

Session `2026-10-13_0418_session`: the staged switch worked 4 of 4 (stage 1 911-1095 ms, the rest 0.2-33 ms);
every one-call restore was followed by 2x "Could not invert matrix" (findings map-camera.md "The staged graphics
switch"). Every item keeps the Performance and Crash safety guarantees and the staged-switch rules (no window
open / close in a setAppConfig frame, the gate, the marker saved before stage 1).

1. **High graphics mode**: renamed from "Highest graphics"; a base `builtin.CheckBox` (as Industry Flows and
   Problem Radar's settings page) in the window's footer, under the tab content. The button tooltip says "High
   graphics mode: on.".
2. **Staged restore** (pm_button `beginUnstage` / `runRestoreStage`, `pm_core.RESTORE_STAGES` = STAGES
   reversed): untick = restore stage 1 (`numMSAASamples`, `resolutionScale`) in the next onStep, then (until
   round 3) shadows, SSAO / reflections, detail, textures, `STAGE_DELAY_FRAMES` apart; the marker is cleared and saved with the
   last stage (a crash mid-restore: the safety net repairs the rest). Stages with nothing to change make no call
   (the last always runs: the marker). Logged `hq off(<why>) after stage K of 5: 5 restore stages`, `hq restore
   stage N/5 keys= ms=`, `hq off(<why>) restored in 5 stages ms=` (4 since round 3, 3 since round 5). The pause menu and a new game keep the one
   call at once (from any state, the staged restore included). Ticked again during the staged restore: the
   stages run again from 1 (keys already high skipped, the snapshot and marker kept). The window frame rule and
   the gate apply to restore stages as to the switch on.
3. **Hide labels / Hide UI** (`gui/pm_hud.lua`). Research (findings gui.md "The HUD filter is base GUI save
   data"): there is no api for HUD visibility and no input action; the base HUD filter window writes
   `getGuiSaveData("").hudFilter` and the default selector's action builds `HudIconManagerConfig{ preFilter,
   ... }` from it when it renders. Built: tick = the player's `hudFilter` kept (also in our own save data, key
   modId field `hud`), the hidden filter written (stations, industries, warehouses, towns, landmarks, vehicles,
   every carrier, costs, income, events, cargo flow; never BASE_NODE), then `preventReactSelector` and one frame
   later `allowReactSelector` (re-renders the selector's action). Untick / pause menu: the player's filter back,
   unless they changed it meanwhile. Not on window close (the player keeps clean shots). Unverified in game:
   whether the icons go at once and which labels the filter covers ("1/20" rates and passenger counts are
   station / vehicle icons; the chevrons are inferred to be vehicle or cargo-flow icons): TESTING.md G3.
   "Hide UI" (footer button): `byId.setVisible("react.game-ui-root", false)` (verified to hold, findings
   map-camera.md "Hiding the game UI"); back after 10 s, when the camera moves, when the mouse moves over the map
   (its terrain position changes by more than 2 % of the distance, after a 0.6 s grace), on the pause menu.
   Unverified: whether Esc, clicks and the camera controls reach the game while the root is hidden.
4. **Random places**: `pm_world` picker `place` = a random point of `getBoundingBox` 8 % in from the edges,
   framed as kind `place` (120 m, 15 degrees; tour: within the range); every framed view's pitch is raised so the
   eye clears the ground under it by 8 m (`cam.clearPitch`, two `getHeightAt`). In "Anything" (weight 2) and the
   tour; an explicit "Random place" button.
5. **Tour in free camera**: not the game's free camera. `toggleFreeCamera` hands the camera to the C++ fly camera
   (own mouse / keyboard input, `isFreeCameraMouseAttached`), and nothing documents `setCameraData` driving it;
   `getCameraData` would no longer show the player's input either, so the tour couldn't notice it. Built instead:
   the tour hides our window (`byId.setVisible(window id)`, as base tool windows, `gui/main/tool_react_util.tl`)
   and, with the Tour tab's "Hide the game UI during the tour", the UI root; the driver keeps stepping while the
   window is hidden (`driver.busy()`). Exit: any camera input (`cam.userMoved`, as before), the pause menu, the
   window closing; the window shows again then; a UI-hidden tour shows the UI after 60 s at the latest (the
   tour goes on, the window stays hidden until it stops).
6. **Ken Burns as an option** ("Ken Burns drift", default on): the drift is a steady motion (rates per second,
   `pm_flight.kbRates`) whose speed ramps in during the glide's last 2 s and out during the next glide's first
   2 s; the glide interpolates between the moving end points, so the velocity is continuous at both ends
   (`tests/.../test_flight.lua`). The hold (5 / 10 / 20 s) is counted from the arrival (hop start + glide), not
   from the hop start. Off: glide from rest to rest, a still hold.
7. **Tour UI**: its own "Tour" tab; labelled rows (fixed 120 px label column): Mode, Source (not for Aerials),
   Hold, Lowest view, Highest view, Closest, Farthest (base `ToggleButtonGroup`s, as Problem Radar's settings),
   the Ken Burns and Hide-the-UI checkboxes, and one wide Start / Stop button (`font-scale-title-4`). The Views tab
   holds only the saved views ("No saved views yet." when empty); the up / down icons stay disabled at the ends.
8. **Camera range**: `cam.RANGE` steps: lowest view Eye level 0.04 / Low angle 0.12 / Drone 0.45 rad, highest
   view Low angle 0.20 / Drone 0.70 / Bird's eye 1.40, closest 25 / 60 / 150 m, farthest 90 / 350 / 900 m;
   defaults = rev 1 (0.04-0.20, 25-90 m). `cam.tourRange` validates (bad index: default; from above to: swapped;
   inside SAFE); the drift's pitch stays inside the range.
9. **Presets / modes**: Ground level (the rev 1 range), Aerials (a continuous drone flight: Catmull-Rom spline
   through waypoints 1.5-4 km apart chosen among towns, stations, industries, water and open country with turns
   below 1.2 rad, inside the map 12 % in from the edges; 32 m/s ramping in over 6 s
   (round 11: 4.5 s, during the glide onto it); the eye 150-290 m over the
   ground under it (a 70 s sine), looking at the path 420 m ahead; heights smoothed over 1.5 s, never below 40 m
   over the eye's ground), Mixed (range 0.04-0.70 rad, 25-350 m, a 30 s flight leg every third hop; round 11: the
   next glide leaves the drone still flying, no ramp out). Picking a mode sets its range; the player can change it afterwards.
10. **Interesting shots** (`pm_shots.lua` pure, `pm_world` SHOT scans; each framing names a look heading):
    train on a bridge (BASE_EDGE BRIDGE under a train; deck height above the terrain scores, >= 40 m stops the
    scan; side-on, the eye at 40 % of the deck height, 90-400 m), crossing water (a train / road vehicle on a
    bridge with `isOnWater` under it; side-on, low), trains passing (moving trains' positions, closest pair within
    150 m, grid-binned; centred, side-on), tunnel portal (the train's edge and its path neighbour, one TUNNEL and
    one not, the shared node within 250 m; from outside, looking into the portal at 0.35 rad), landing or
    take-off (flightState TakeOff / Landing / Approach, 15-400 m over the ground; the camera on the ground ahead
    along `aircraftState.dyn.velocity`, looking back), busy street (road vehicles' densest 150 m cell, two shifted
    grids; low along its main axis), skyline (biggest town from a 1100 m ring: water first, then a point not
    higher than the town + 30 m; low), viewpoint (4 towns, rings at 700 / 1200 m, the highest rise >= 40 m, water
    between a bonus; from the hilltop looking down), train at a platform (standing and loading / unloading /
    departing; longer and departing first; along the platform), oldest vehicle (model `availability.yearFrom`,
    cached per model; kept best across clicks; round 17: shown again only after its cycle), fastest vehicle (MOVE_PATH speed; followed after the jump),
    longest train (now framed side-on). Replaced: Busiest station, Biggest town, Vehicle on a bridge, Aircraft at
    an airport. Not built (cost): level crossings (the node -> edges map per node), ships under bridges (an
    octree query per ship). The strong ones are in "Anything" and the Ground level / Mixed tours.
    The look heading -> camera angle offset is measured once per session (`getEye` / `getCenter` against
    `getCameraData`'s angle, `cam.measureLookOffset`, logged `look calibrated: ...`); until a reading works it is
    taken as 0 (to verify: G10a).

## Open work

- Round 14 (above): run CC1-CC5. After CC4: if `centre fit` shows the base height fits, use `max(getHeightAt,
  getBaseHeightAt)` as the solver's ground (pm_flight `solveEye`'s `ground`) and replay the 0633 reports; a river's
  water level likewise (water meshes' `waterLevel`). Decide with the user whether High becomes the default Look.
  After CC3: the locks' meaning into findings environment.md; if the pace is even, the attached cutscene is the
  route for orbit / fly-by templates (PLAN.md "Round 13" item 3c route 2).

- Run TESTING.md in game: G1-G10 and S1-S12 (round 2), F1 (incl. the long session) and F2-F10 not yet seen, the
  rest of P1-P13 and C1-C11; then release (cover done, no gallery slides yet).
- After F3: keep only the follow-release call that works; finding in `docs/findings/map-camera.md`.
- After G3: settle "Hide labels" (does the selector refresh work; which labels stay) and add the finding; after
  G10a: note the measured look offset in `docs/findings/map-camera.md`.
- Rev 2 phases 2-4 (above; Hide UI of phase 2 built in round 2).
- After G20: does Esc reach the game while the UI root is hidden? The base code says no (round 4, 5); the pause
  key (Space) is the built escape hatch. Add the result to `docs/findings/gui.md` "Input actions don't reach a
  hidden GameUIRoot" (mark it verified or correct it).
- After G16: the zoom limit at low pitch (is ~4137 m pitch-independent?); tune `cam.ZOOM_LIMIT` and add the
  finding to `docs/findings/map-camera.md` "Camera zoom limit".
- After L1-L5: which calls the Light tab really needs (env copy vs the cloud command; does the environment's
  day of year / sun rotation hold or get reset by the game each frame?), the sun-time model (L3), and a finding
  in `docs/findings/map-camera.md`.
- Phase 4 (Looks): run K1-K13; then settle the sun calibration (`pm_looks.SUN_CAL`, K10), the rain threshold (K6)
  and Low clouds' heights (K7), and add the findings (does a look switch show; dayOfYear and snow / foliage).
- Round 11 looks (below): run K14-K19; tune the pushed values from the user's verdict (`tools/gen_photo_looks.py`
  SKY / WATER, then `uv run tools/gen_photo_looks.py`); decide on depth of field (a PC-only shader variant mod or
  not, LOOKS.md "Depth of field").
- Round 12 looks (below): run K21-K25 (K20 is superseded by K23); tune the haze looks in `tools/gen_photo_looks.py`
  HAZE from the verdict (Soft background: `mieScatteringScale` = veil strength, `mieScaleHeight` = how far up it
  reaches, `miePhaseG` = glow towards the sun vs elsewhere).
- After G22: does a class on a FlowLayout / BoxLayout get its innerSpacing / padding in game? Mark the finding
  (findings gui.md "Inline styleSheets don't apply to layouts") verified, and the ui-guide "Spacing" rule.
- G23 settled (three sessions, every probe fell back): the probe is dropped and only the footer button pushes the
  free camera (round 9). Open: whether the mouse attachment turns the view in the footer's camera mode.
- After G21e / V1: does another tool (or the footer's camera mode) bring the hover back while labels are hidden or
  a move runs? If V1 still shows hover during tours, re-fire `preventReactSelector` on `getActiveTool` changes
  (checked rarely) or find what else drives the hover.
- After V2-V5: refit the camera model with the new `cam trace` / `eye check` lines (wider d and p: flights,
  Bird's eye); if `eye smoothness` still shows jerk spikes, look at the frames around `worst f=`.
- Round 12 camera (above): run CA1-CA7. After CA5: the `eye spike` reports say where the game leaves the camera
  model (engine eye vs `model=`, centre vs `model z=`, a `CLAMPED` send); fix that in the solver and add it to
  findings map-camera.md "Single-frame eye spikes during tours". CA6 / CB5 settled (session
  `2026-10-14_0606_session`): the GUI state has no `io`, so the keys-file path is closed and its code removed
  (PLAN.md "Round 13" item 4).

## Rev 1 feedback round 3 (crashes 2026-10-13_0522 / _0524 and screenshots; built in code 2026-10-13, untested)

1. **No shadows in High graphics mode.** Two staged crashes right after stage 4 `keys=shadowQuality` (3x "Could
   not invert matrix", native crash the same second; desert map / 240k people / camera straight down, and the
   sub-arctic line manager test save). With the two one-call crashes: 4 of 4 on a `shadowQuality` change
   (findings map-camera.md "Changing render-buffer settings at runtime crashes"). `pm_core`: `shadowQuality` out of
   `KEYS`, `BOOST`, `STAGES` and the value validation; 4 stages each way. An old marker that still holds it is
   accepted, its shadow value ignored. Tooltip and description: "Shadows stay at your setting: changing them
   while playing can crash the game on Mac." The DEV probe's boost dropped it too.
2. **Narrow window** (`docs/ui-guide.md`): content 440 px inner (`CONTENT_W`); every button row is a FlowLayout
   in a `Component` of a fixed width (`FLOW_W` 424), as the base vehicle window's cargo icons, so rows wrap
   instead of stretching the window (~1400 px before: a bare FlowLayout's preferred width is one line). Tour
   choice groups: `ToggleButtonGroup{ layout = "Flow" }` in a box of the remaining width (`CHOICE_W` 300), their
   labels in a 120 px column that wraps (CSS `sqpm-label`); hints and the status line wrap at 424 (`sqpm-wrap`).
   To verify in game (G11): the width, and that de / ru labels wrap without clipping.
3. **Even spacing**: every row item (buttons, view-row buttons, checkboxes) has a 4 px gap inside it (padding
   right and below, `ITEM_GAP`); Flow toggle groups get the base 4 px `innerSpacing` (separate buttons, the
   selected one highlighted); labelled rows and the Tour checkboxes 3 px above and below (`ROW_GAP`).
4. **Footer**: 8 px padding on all sides; the three checkboxes 12 px apart (a 4 px gap read as touching next to
   a label), wrapping if needed. **Hide UI** is a checkbox: ticked while hidden, unticked when the UI is back.
   It stays hidden until Esc (the pause menu restore), a new game, or unticking (not reachable while hidden):
   the 10 s timer and the mouse / camera triggers are gone (user: moving the mouse to frame the shot brought the
   UI back).
5. **Start tour**: a base Button with the base `primary` class (accent background, `default.css.lua`), body
   text, no inline styleSheet (the first build's inline size + title font showed as bold plain text).
6. **Tour sources are checkboxes** (`cam.TOUR_SOURCES`: Random subjects, Random places, Saved views,
   Interesting shots; default all but Saved views). The tour takes the ticked ones in turn, one per hop
   (`cam.tourNextSource`); a source with nothing this hop is skipped (all empty: the tour stops with a status).
   Each subject source cycles its own kinds (`cam.SOURCE_KINDS`). Unticking the last one is refused
   (`cam.toggleSet`; status "Keep at least one ticked."). Saved views alone: list order, no Mixed flights (as
   before). Logged `tour sources ...`, the hop line names the source (`tour random town (...)`).
7. **Aerials options** (Tour tab, Aerials and Mixed): "Flight leg" 30 s / 1 min (default) / 2 min / 5 min
   (`cam.LEG_SECONDS`): an Aerials leg ramps to rest, then the next starts over a new area (`newArea` in
   pm_driver: a candidate of the ticked subjects at least 3 km away, else a random inner-map point; a glide
   there), a Mixed leg goes back to the hops (was a fixed 30 s). "Fly over" checkboxes (`cam.FLIGHT_SUBJECTS`,
   all on, one stays ticked): Towns, Landscape (land samples, hills weighted up), Water (sea / lakes / coast:
   `isOnWater`), Rivers (narrow water: `cam.waterKind`, land on both sides 150 m out along one axis), Rail lines
   (positions of running trains), Points of interest (stations incl. airports / harbours, industries).
   `world.flightCandidates(subjects)`: 24 random terrain samples (48 with rivers ticked), up to 4 more
   `isOnWater` per water hit; once per waypoint (about a minute) and per new area. No river API exists (only
   `isOnWater` and the navigable `waterLevel`; `api/engine.d.tl`), so rivers are sampled; a subject the map has
   none of adds nothing and is logged (`flight candidates ... rivers=0 (none found)`); with no candidates the
   drone flies on ahead (pm_flight's fallback), never to a made-up "river".
8. **No 60 s fallback for the tour's hidden UI**: it came back by itself during an Aerials tour (user). The UI
   root hidden for a tour comes back only when the tour stops (camera input (since round 4 during a flight only
   a pan), the pause menu, the pause key (round 4), the window closing, a new game), the same rule as the Hide
   UI checkbox.

## Rev 1 feedback round 4 (built in code 2026-10-13, untested: TESTING.md G16-G20, L1-L9)

Every item keeps the Performance and Crash safety guarantees and the staged-switch rules (no shadows, no window
open / close in a setAppConfig frame); nothing here calls setAppConfig.

1. **Horizon shots** (user: "the camera shots are too limited, we should be able to get higher up but looking
   across the horizon"). The camera is centre + distance + angle + pitch, so the eye height is d·sin(pitch); a
   high camera looking level needs a low pitch and a long distance with the centre far ahead. Camera tab:
   "Horizon" (250 m up, 0.075 rad = 4.3°, d ≈ 3330 m) and "High horizon" (800 m, 0.10 rad wanted). Built by
   `cam.horizonShot`: the eye stays above the current centre (its height counted from the ground there, one
   `getHeightAt` each under the eye and the new centre), the angle kept, the centre d·cos(p) ahead along the
   heading. **Zoom limit**: `setCameraData` past the vanilla limit (~4137 m at pitch 0.95, findings map-camera.md
   "Camera zoom limit") eases back within a second, so `cam.ZOOM_LIMIT` = 4000; a view that needs more is
   clamped there and its pitch raised to keep the height (`cam.horizonFrame`; High horizon: d 4000, p ≈ 0.20 =
   11.5°), logged `horizon clamped by zoom limit d= p= (wanted d= p=)`. Whether the limit depends on the pitch is
   unknown: G16.
2. **Horizon tour range**: Highest view gets a 4th choice "Horizon" (pitch ≤ 0.09), Closest a 4th (1000 m),
   Farthest a 4th (3500 m, `cam.MAX_DIST`); appended, so the old indices and presets stay. Horizon + 1000-3500 m:
   every hop is 40-300 m up, nearly level. Aerials / Mixed: "Look" Down (as before) / Horizon: the drone looks
   along its own heading (the path tangent at the eye), the centre `F.horizonAhead(h)` ahead (pitch 0.07, the
   distance at most 97 % of the zoom limit, pulled in while it would lie off the map), flying a little higher
   (`F.HORIZON.alt` 300 m on average). Taken at each flight leg's start.
3. **Mouse look while flying** (user: "while in aerial mode can you move the mouse around like in free camera
   mode?"). During a flight (Aerials, Mixed legs, their glide in) the player's turn / tilt / zoom no longer stops
   the tour: `cam.flightInput` reads it from the difference between the view we set last frame and
   `getCameraData` (any change above `cam.LOOK_EPS`, far below the old stop tolerances, so slow mouse moves count),
   `F.lookStep` adds it to an offset { angle wrapped, pitch ±0.9 rad, zoom log −0.7..+1.0 } and `F.applyLook`
   puts it on every flight view (the eye kept 30 m over the ground under it, distance within the zoom limit).
   "Look returns to the path" (checkbox, default on): 0.6 s after the player lets go the offset decays to ~5 % in
   5 s; off, it stays. Only a pan (the centre moved more than 5 m or 2 % of the distance in a frame without a zoom;
   a zoom towards the cursor moves the centre, so a zooming frame ignores the centre) or Esc stops the tour.
   Hops (Ground level, Mixed hops) keep stopping on any camera input. Logged once per flight `tour flight: mouse
   look kept as an offset (...)`. The Aerials tooltip says so. Untested assumption: the camera's own smoothing
   of mouse input shows as per-frame differences we can add up (G18).
4. **Esc while the UI is hidden** (research, base code): `game.tl:803` forwards `IA_MENU` (Esc) to the
   GameUIRoot node, and the base comment right above the proxy root's actions (`game.tl:746-747`) says "Input
   Actions declared here are available even when Game UI is not visible. Note that forwarding to an invisible
   GameUIRoot is still impossible." Input actions of an invisible hierarchy don't fire (`gui.d.tl`
   `InputActionState.Enabled`: "except if disabled/invisible due to hierarchy"), and every mod plugin point
   (`MainModButtonAreaExtension`, `ModEntryPointExtension`) sits inside that root, so a `useInputAction("IA_MENU")`
   of ours would be hidden too (and while visible it could steal Esc from the pause menu). So Esc very likely does
   nothing while hidden (G20 settles it). What works while hidden: the proxy root's own actions (`gamePause`,
   `IA_GAME_PAUSE_OR_CYCLE_SPEED`: Space) and every `openPauseMenu` event (Cmd+Q, quit requests: findings gui.md).
   Built: while the root is hidden (Hide UI or a tour's hidden UI) `pm_hud` reads `GAME_SPEED.speedup` once a
   frame (as the base GameSpeedHelper does every frame); a change between paused and running (the pause key; the
   speed throttle never pauses) after a 30-frame settle (a freeze command of ours landing) brings everything
   back: the tour stops (`hud.onEscape` → `driver.stopTour("pause key")`), Hide UI unticks; logged `ui: pause key
   while hidden, bringing the UI back` and `ui shown (pause key)` (or `ui shown (pause menu)` for Esc / Cmd+Q).
   The game's pause toggles too (the key's own effect). Tooltips (Hide UI, the tour's hide checkbox): "Press Esc
   or the pause key (Space)". Finding: `docs/findings/gui.md` "Input actions don't reach a hidden GameUIRoot".
5. **Phase 3: Light & weather**: below.

## Rev 1 feedback round 5 (crash 2026-10-13_0558; built in code 2026-10-13, untested: TESTING.md G1, G2, G12)

1. **High graphics mode without geometry, terrain and grass.** `2026-10-13_0558_session-crash` (only Photo Mode
   enabled, "New Game - desert", estimatedMb=4581, 1015 vehicles): `hq stage 1/4 textureQuality,
   terrainTextureQuality ms=1710` passed, `hq stage 2/4 keys=geometryQuality,terrainQuality,grassQuality ms=1.1`,
   then in the same second the fatal assert `StaticBuffer.cpp:743 Render: Assertion 'it !=
   typeData.material2offsetAndCount.end()' failed` on the Main Pool threads, crash. The same keys had changed
   without a crash 9 times as a switch stage (sessions `_0418`, `_0522`, `_0524`, `_0525`; `_0522` on this very
   save), 2 times as a restore stage and ~30 times in one-call switches (DEV probe, `_0418` restores), so it
   doesn't crash every time, like shadows. Rule now: only keys that reload images / screen effects (textures, terrain
   textures, SSAO, SSR, MSAA, resolution scale), never ones that rebuild meshes / render buffers (shadows,
   geometry, terrain, grass). `pm_core`: those three out of `KEYS`, `BOOST`, `STAGES` and the value validation;
   3 stages each way (textures; SSAO / reflections; MSAA / resolution scale); an old marker that still holds them
   is accepted, those values never written (switch, staged / pause-menu restore, safety net). Tooltip,
   description, modinfo: "Shadows, geometry, terrain and grass stay at your setting: changing them while playing
   can crash the game." The DEV probe's boost dropped them too. Findings map-camera.md "Changing render-buffer
   settings at runtime crashes".

## Rev 1 feedback round 6 (built in code 2026-10-13, untested: TESTING.md G21-G28)

User screenshot of the Tour tab (round 5 build) and four requests. Every item keeps the Performance and Crash
safety rules above; nothing here calls setAppConfig (graphics: the safe set only, unchanged).

1. **Layout (root cause, not a value tweak).** None of the round 3-5 spacing showed: rows' ToggleButtonGroups
   touched, checkbox labels ran into the next box, Start tour touched the row above, the footer sat on the window
   edge. All of it was an inline `meta.styleSheet` (padding) on a `builtin.BoxLayout` (per-item wrappers, rows,
   the footer, the content root). react hands a builtin's meta.styleSheet to `builtin.WithComponentParams`, which
   styles a Component; a layout isn't one (`gui/main/react.lua` ~375-385, `builtin.d.tl:634-646`), and the base
   never puts an inline sheet on a layout. The gap between a layout's children is its `innerSpacing`, set only by
   a stylesheet rule (base `ToggleButtonGroup!flow FlowLayout`, `CheckBox BoxLayout!buddy-layout`); padding on a
   layout works through a class rule (Timetables' `!celmi-tt-content`). Built: the per-item wrappers are gone;
   layouts carry classes, three rules space the whole window: `sqpm-gap` innerSpacing 6/6 (every column, row and
   wrapping flow), `sqpm-checks` 12/6 (rows of checkboxes: Sources, Fly over, footer), `sqpm-content` padding 8 +
   innerSpacing 8 (the content root: off the window edges, between tabs / footer / status). Headings 4 px inline
   padding (a TextView is a Component), a 4 px spacer Component above Start tour, a 1 px separator Component above
   the footer. 12 rules in all (8 + the shared 4). Finding: `docs/findings/gui.md` "Inline styleSheets don't
   apply to layouts"; rule for every mod: `docs/ui-guide.md` "Spacing"; offline guard `test_window.lua`.
2. **"This place" tour** (`pm_place.lua`, driver `placeAdvance`, `pm_world.nearby`): a fourth Mode; the camera
   centre at Start is the place; Area Small / Medium / Large = 80 / 250 / 600 m (`place.AREAS`, default Medium).
   Each hop: the next heading slice (8 per round, every slice once, shuffled, a new round never starting next to
   the last slice), a pitch band (low / middle / high third of the pitch rows; preset eye level to drone), a
   distance (place points 0.2 r .. 1.2 r, subjects 0.08 r .. 0.5 r, geometric); the target a nearby subject for
   about half the hops (constructions from the octree circle query, running vehicles, people; looked up at the
   start and every 6 hops; a moving one re-read and skipped when gone or out of the area) else a random point
   within 0.6 r. Ken Burns and the hold as Ground level (the same `startHop`). It stays until stopped (camera input,
   Esc, the pause key, the window). Switching the Mode during a place tour keeps the place (the next tour uses the
   new mode). Logs: `tour place x,y r= subjects=`, `place subjects r= buildings= vehicles= (read N of M) persons=
   ms=`, `tour place <kind> entity=... to=` / `tour place point to=`.
3. **Hide labels and hover** (`pm_hud`): `preventReactSelector` keeps the default selector from building its
   hover selector and tooltips (`selector_react_util.tl:194-232`): the highlight under the mouse, the entity
   tooltip and click-to-select are off while prevented. So the labels checkbox ("Hide labels and hover") fires
   prevent when it hides the labels and keeps it, and fires allow when they come back (untick, pause menu, tour
   end, game start repair). A tour start fires prevent again while hidden (a remounted selector starts allowed).
   While it is on a click on the map opens nothing (tooltip says so).
4. **Camera mode** (`pm_hud`, pure `pm_cammode.lua`): the base `FreeCamTool` (`gui/main/free_cam_options.tl`,
   the game bar's free camera) pushed with `game_react_globals.getDefaultToolStackApi().push(tool, nil, {}, true)`:
   the game hides its UI itself and Esc / back pop the tool natively (its options recipe lives in
   GameUIProxyRoot), so the UI can't get stuck. Findings gui.md "The base free camera tool from a mod".
   - Tours: "Camera mode during tours" (default on; round 7: "Try camera mode during tours", off by default, see
     "Rev 1 feedback round 7" 7) replaces "Hide the game UI during the tour". At Start the
     look offset is measured (normal camera), our window hidden, the tool pushed (the mouse detached if it is
     attached to the free camera's look). Probe: the next frames compare the view we set with `getCameraData`
     and `getCenter` / `getEye` (`cammode.matches`); a match → `camera mode: setCameraData drives the free
     camera`; none within 2 frames → `camera mode: setCameraData ignored -> fallback hidden UI`: the tool popped,
     the UI root hidden by us (escape hatch, pause menu, start restores as before), and later tours of the session
     go there directly. While on, `getActiveTool` each frame: gone (Esc / back) → `camera mode: left with Esc /
     back`, the tour stops, window back. Every tour end pops the tool (`camera mode: off (tour ended)`). Unticked:
     the UI root is hidden for the tour (the user: either always hide the UI or camera mode).
   - Footer: a "Camera mode" button replaces the Hide UI checkbox (the hidden UI could not be brought back from
     the window). It pushes the same tool (no tour, the player flies the free camera); Esc returns natively,
     logged `camera mode: left (button session)`. If the tool can't be pushed, Hide UI runs instead (Esc / the
     pause key; restored on the pause menu and every start, independent of the window: the plugin's onStep and
     onEvent run with the window closed).
   - Inferred, to check (G23): whether setCameraData drives the free camera at all.
5. **Tour performance**: "Hide labels during tours" (default on: fewer HUD icons, back after the tour); "Pause the
   game during the tour" (default off: the Light tab's freeze, unfrozen at the end only if the tour froze it);
   flight legs plan all waypoints at their start (one candidate lookup per leg, none mid-flight; verified: before
   this the lookup ran inside `extendPath` whenever the path ran short, about once a minute); SQPERF
   `tour_advance`, `tour_flight_start`, `place_subjects`. Camera mode hides the whole GUI (no GUI layout while the
   tour runs). See Performance "Round 6 additions" for what else could help.

## Rev 1 feedback round 7 (built in code 2026-10-13, untested: TESTING.md R1-R10)

From the user's session `2026-10-13_0733_bench-s3-683079` (High graphics, tours of random places, the camera
tab's shots) and six requests. Nothing here calls setAppConfig or opens / closes a window; no react hooks added.

1. **Terrain stutter (the main issue): eye space.** setCameraData places the camera around a centre on the
   terrain (eye = centre ground + d * sin p), so every glide, Ken Burns slide and flight whose centre slid over
   uneven ground bobbed the eye with each bump under the look-at point ("it follows the terrain map"). Now
   every automated move is planned as an eye pose (`pm_flight` "Eye space"): planned views carry a reference
   ground `g` (the terrain at the move's ends, one `getHeightAt` per hop end, interpolated by `cam.lerpView`,
   raised by the Ken Burns pedestal), so the eye path is as smooth as the plan; each frame `F.solveEye` walks
   the look ray from the planned eye to the real ground (a flat-ground step, secant steps only in the direction
   the ray points to, regula falsi once a meeting point is bracketed; the search starts where last frame's
   stood) and sends that point as the centre, with distance and pitch computed from the eye to it: the eye lands
   exactly where planned, the look carries the search's leftover (offline on bumpy test terrain: below 0.02 rad,
   above 0.01 in 4 of 3600 frames, when a crest stops hiding the ground behind it). A clearance lift keeps the
   eye above the ground 1.5 s ahead of it (at most 12 m or 0.8 of the planned height, so eye-level shots stay
   low), rising with a 0.5 s and settling with a 2.5 s time constant after a 1.5 s hold, so it rises before
   hills and never pops. A nearly level look that meets no ground within the zoom limit (or the map,
   `F.rayInside`) takes the centre there: a slightly steeper pitch, changing only with the far ground. Flights
   plan their eye (altitude above the smoothed ground 150 m ahead) and look (path point or horizon) the same way.
   The manual Orbit keeps its plain view: it turns around a fixed centre, its eye height never changes. "eye
   check" log lines (planned eye vs `getEye`, 3 per move) test the placement model in game (TESTING.md R1).
2. **Ken Burns.** `F.kbRates` draws a main move per shot (push 28 %, truck 24 %, pedestal 26 %, orbit 11 %, tilt
   11 %), the others at up to 35 % of their amount, random signs, and a pace of x1.0-x2.5 (x1.0 = the round 2
   speed). Pedestal raises / lowers the reference ground (the eye moves straight up or down) with a little tilt
   that keeps the subject in frame. The glide's ease-in and the hold counted from the arrival are unchanged.
   Logged per hop as `kb=<move> x<pace>`.
3. **Wander** (named so: "drift" is the Ken Burns move): `F.newWander` / `wanderView`. The eye circles the place
   on a breathing radius (0.55-1.05 of the area, never through the middle) with a slowly turning, meandering
   bearing (one turn in 6 min), so it moves in x and y, in and out; its height follows from a pitch towards the
   target that swings inside the angle range; the look eases between targets (nearby subjects from
   `world.nearby`, a moving one re-read, else points of the area) every 10 s, heading and pitch smoothed. Starts
   with a glide from the current view into the moving path. Camera tab "Wander" (next to Orbit; around the
   middle of the view, radius = its ground distance 60-800 m, pitch +-0.12 around the current one; stops on
   camera input, Orbit, the window closing) and Tour mode "Wander" (Area and angle rows; the window hides as for
   every tour). Logs `wander on (camera move|tour) x,y r= pitch a-b subjects=`, `wander look at <kind> x,y`,
   `wander off (...)`.
4. **Bird's eye inverted the WASD keys.** Our side was as meant: the shot kept the current angle (no 180° turn;
   the session's four `shot bird view=...,1.450` lines kept the angle and the next reads showed it unchanged)
   and 1.45 rad is below the vertical (pi / 2), with the look offset (+pi) only used for headings. So the game's
   camera treats a pitch that close to straight down differently (inferred: past its own tilt limit, where its
   keyboard pan turns around); not testable offline. Fix: Bird's eye 1.30 (74.5°), the tour's "Bird's eye" angle
   1.30, and `cam.PITCH_MAX` 1.35 caps everything sent (`SAFE.pMax`, mouse look). TESTING.md R4 checks it and, if
   needed, reads the game's own steepest tilt from a saved view. Finding: map-camera.md "Bird's eye at pitch 1.45
   inverted the keyboard pan".
5. **Tooltips on every control.** Only the "Horizon" option of the angle row had one: the other options of the
   Tour tab's choice rows (Hold, the angle and distance rows) passed `nil`. Buttons, CheckBoxes and the
   ToggleButtonGroup options all reach the same path (the base group copies each button's `meta` onto its
   ToggleButton, `gui/main/builtin.lua` ~868-885; react hands `meta.tooltip` to `WithComponentParams`,
   `react.lua` ~364-375), so the fix is filling them: every option, plus a tooltip on each row label (a
   TextView). `test_window.lua` fails when any Button, ToggleButton, CheckBox or option of any tab / Tour mode
   has none.
6. **"Lowest view vs Closest".** The rows are now "Angle from" / "Angle to" (how steeply the camera looks down)
   and "Distance from" / "Distance to" (how far away), each label and option with a tooltip saying which; ja / ko
   / zh read "minimum / maximum angle / distance".
7. **Camera mode, honestly** (session evidence: `camera mode: on (tour)`, then in the first probe frame
   `setCameraData ignored -> fallback hidden UI (set d=120 read d=120)`). The read-back equalled the view set,
   so the eye / centre part of `pm_cammode.matches` failed: getEye / getCenter reported another camera. The
   probe frames compared the pre-tour view (the first glide had barely started), which a free camera left where
   it was would also have matched, so the free camera reported an eye / centre of its own geometry: it is a
   separate camera that setCameraData doesn't move, and the API has no setter for it (`gui.d.tl` camera:
   setCameraData, setManualCamera, focusPosition, followEntity; getEye / getCenter read only). Inferred, to
   confirm (findings map-camera.md "The free camera ignores setCameraData", TESTING.md R6). So: "Try camera mode
   during tours" (renamed, tooltip says experimental, **off by default**): tours use the hidden-UI path; the
   footer's Camera mode button stays (manual free camera). The probe now counts a frame only once our view has
   moved away from the entry view (`pm_cammode.moved`, up to 120 frames) and logs each counted frame in full
   (`camera mode: probe frame N (waited W) set= read= eye= centre= |eye-centre|= match=`).

## Rev 1 feedback round 8 (built in code 2026-10-13, untested: TESTING.md U1-U12)

From the user's session `2026-10-13_0856_sqot-dev` (wander and hop tours, Bird's eye, eye checks) and a
screenshot of the Subjects tab. Nothing here calls setAppConfig or opens / closes a window; no react hooks added.

1. **Option sets** (user: "This layout is too cumbersome, need a better pattern for many options like this. Same
   for all ghost button styles. If they just had outlines it would be better."). The base default Button is
   borderless with 8 px padding: rows of them read as tall blocks with big gaps. Researched: the base has an
   outlined button already, `default.css.lua` `Button!secondary` (the accent contour on the base contour
   nine-patch, with the base hover / pressed / disabled states; used by the game bar's weather widget, the map
   editor, the vehicle store); borders in TF3 CSS are `borderImage` + `borderColor` (no border width property);
   a base `builtin.ComboBox` (`builtin.d.tl` ComboBoxParam; base mod settings `script_param_util.tl`, the cargo
   layer) with per-item tooltips on the items' TextViews. Built (one pattern, `docs/ui-guide.md` "Option sets"):
   every action button is `secondary` + a compact class (padding 4 / 6: rule `sqpm-small`); long action sets
   (Subjects 11 + 12, Camera shots 6, Light presets 7) are grids of equal cells (`sqpm-cell`: the label 122 px,
   centred, wrapping; three cells + two gaps = 414 of the 424 px row) in the existing fixed-width FlowLayout box,
   so they wrap by the window width; the Camera moves (Orbit, Wander, Follow, Cockpit) are base ToggleButtons of
   the same cell size; the Tour tab's Mode (5 long options) is a ComboBox (values "1".."5", each item's tooltip;
   the closed box shows the selected mode's); the other Tour choice rows (2-4 short options) stay
   ToggleButtonGroups with compact options; Start tour stays `primary`; the Views tab's Save view, Go and row
   icons and the Light tab's step buttons are compact outlined buttons; the footer's Camera mode is an outlined
   button in the checkboxes' wrapping row (on their line when it fits). 2 rules more (14 with the shared 4).
2. **Footer padding, the cause.** The footer was inside the `sqpm-content` root column, and the selector matched
   (the base styles `R::Recipe > BoxLayout` the same way), but the rule's `padding` on a BoxLayout did nothing:
   the footer sat ~6 px from the window edge (the window frame only), while the tab text sat ~20 px in thanks to
   the base `TabWidget::Content` padding (8, a Component). No base rule pads a layout. Fix: the recipe's root
   BoxLayout holds one Component with an inline padding of 8 (the content off every window edge), the footer
   (separator, controls, status line) sits in a Component with an inline padding of 8 left and right (the tab
   page's inset), `sqpm-content` keeps only its innerSpacing. Finding: `docs/findings/gui.md` "Padding applies
   to Components, not layouts" (inferred; TESTING.md U4 confirms).
3. **Height bumps: the game's pitch offset.** The round 7 eye checks showed getEye 14-76 m (one 549 m) above
   the planned eye, never below. Reconstructing the centres: getEye lay in the look's vertical plane, at the
   distance set from the centre set, on a line ~0.22-0.34 rad steeper than the pitch set (also at pitch 1.19 ->
   1.42, so an offset, not a floor); getCameraData read back exactly what was set. Inferred (findings
   map-camera.md "The game's eye sits steeper than the pitch set"): eye-centre elevation = pitch + delta. It also
   explains round 7's Bird's eye at 1.45 turning the keys around (1.45 + 0.23 > pi / 2). Why it bumped: the
   solver kept the planned eye exact only for delta = 0; with delta the real eye sat d (sin(e + delta) - sin e)
   too high, which changes whenever the solved centre's distance d jumps (a crest, a valley under the look).
   Built: `pm_flight.pitchSample` (getEye over getCenter minus getCameraData's pitch, refused when the game's
   distance or centre doesn't match the data), `pitchUpdate` (first sample as is, then smoothed over 2 s, clamped
   -0.2..0.7), measured every frame of a move (`D.step` -> `sendPlanned`; not while camera mode is probed or a
   follow runs) and once at the start of a session's first move (`pitch offset measured ...`). `solveEye` takes
   `st.pOff`: the look at least delta steep (the game takes no pitch below 0), the elevation at most 1.48, sends
   `elevation - delta`. Semantics: a hop's views (framings, saved views, Ken Burns drift) are in the game's pitch
   and get `+delta` for their eye pose (`F.poseOf(v, off, dp)`: the eye where the game would put that view on the
   reference ground, so framings look as before but smooth); wander and flights plan elevations directly (the
   wander's start view and the flight's glide end converted). `cam.PITCH_MAX` 1.35 -> 1.30 (1.35 + delta is about
   straight down). Jumps, shots, Orbit, Go: unchanged (the game's pitch sent directly). Diagnostics: the eye
   check line adds `set=` (the view sent), `centre=` (getCenter), `g=` (our ground at the centre) and `off=`; a
   per-frame `cam trace` (read / eye / centre / height above terrain / plan / set / g / sample / off / where the
   centre shows on screen) for the first 40 frames of the session's first two moves, every move with "Debug:
   performance log" On (TESTING.md U8, U9). Closed loop vs a fixed clearance: the measured offset is a closed
   loop on the game's own geometry (it adapts if the offset depends on distance or pitch); a clearance margin
   couldn't remove the dependence on d. Open: what the offset is (screen position of the centre, `scr=`),
   whether it varies with distance (the 1.2 km viewpoint hop fitted 0.49), whether the centre's z is
   getHeightAt there.
4. **Saved views in the pool** (user: "If you save a shot, that should count in the interesting shots pool").
   A new subject kind "saved" (`pm_world` PICKERS.saved: a random saved view as a subject with its own view; the
   list from the window through `driver.viewsProvider` -> `world.savedViews`): one kind of the tour's
   "Interesting shots" source (`cam.SOURCE_KINDS.shots`, cycled with the 9 shots: about one hop in ten) and of
   Anything (`cam.ANY_KINDS` weight 1.2, as the strongest shots; none saved: skipped like any empty kind). The
   view is used exactly (no reframing, no clearance change), with half the Ken Burns drift (as the saved-views
   tour). The "Saved views" source still plays them in list order. Tooltips of Anything, Save view and the
   Interesting shots source say so (13 languages). Offline: test_world (pick, Anything's share, corrupt / failing
   list), test_cam (in both pools), test_driver (a hop to exactly the view, a jump).

## Rev 1 feedback round 9 (built in code 2026-10-13, untested: TESTING.md V1-V10)

From the user's session `2026-10-13_1755_session` (This place, Mixed and Wander tours, Orbit, the footer's
Camera mode; 80 `cam trace` and 12 `eye check` lines) and two requests. Nothing here calls setAppConfig or opens
/ closes a window; no react hooks added.

1. **No hover during automated moves** (user: "The tour still has hover and mouse interaction with it. It should
   by default not."). While a tour (any mode), the Wander (camera move or tour) or the Orbit runs, the default
   selector is prevented (`pm_hud.setAutoHover`: `preventReactSelector` at the start and again 2 and 30 frames
   later, since a selector remounted meanwhile starts allowed), labels or not: no hover highlight, no entity
   tooltip, no click-to-select. Allowed again when the move ends by any path (camera input, Esc / the pause menu,
   the pause key, the window, Stop, a camera error; a new game starts with a fresh selector, nothing is saved),
   unless "Hide labels and hover" keeps it prevented. The driver tells the hud from `bump` (every state change)
   when `moving()` flips (`D.onAutoMode`); one move replacing another (Wander <-> Orbit, a tour over a wander)
   runs inside `switching`, so there is no allow-prevent flicker. Labels shown during a move (the checkbox, a
   tour's own labels at its end) re-render the selector to read the filter (allow) and prevent it again two
   frames later. No checkbox: always on (user: "off by default without needing a checkbox"); "Hide labels during
   tours" now only hides the labels (tooltip and 13 languages changed). Mouse look during flights is camera
   input, unaffected. Why round 6's prevent didn't hold during the session's tours is open (findings gui.md: the
   free camera push / pop of the footer button and the first tour's probe likely remounted the selector).
2. **"Try camera mode during tours" removed** (user: "we can get rid of try camera mode during tours"): the
   checkbox, its two strings (13 languages), `D.setTourCamera` / `S.tourCamera`, the probe (`H.cameraCheck`,
   `D.cameraCheck` and the step's probe branch) and `pm_cammode.lua` with `test_cammode.lua` are gone; a tour
   always hides the window and the UI root. The footer's Camera mode button stays (`H.ACTIVE_GRACE` moved into
   pm_hud). Three sessions showed the free camera ignores setCameraData (findings map-camera.md).
3. **The game's camera model** (findings map-camera.md "The game's camera model"): fitted to the session's trace
   and eye checks. `getCenter` = (x, y, getHeightAt + 4.0) (11 of 12 checks and every traced frame; over water
   4.0 at ground -1.0: water level 0 + 4, inferred); `getEye` at the distance set from it, in the look's plane,
   at elevation `e = p + k(d) (pi/2 - p)`, `k(d) = 0.0768 + 0.0102 sqrt(d)`: rms 0.0036 rad, max 0.011 over d
   30-400 m, p 0-0.67. Compared: a constant offset (round 8) 0.054 / 0.100, `a + b sqrt d` without p 0.024 /
   0.061, `cos p` and `cos^2 p` shapes 0.013 / 0.0085, linear or log in d 0.007. Not a terrain clearance under
   the eye (`hat` 9-16 m varied freely), not the near plane (the distance is the one set). Round 8's jerk: it
   smoothed one measured offset over 2 s, but the offset changes with d, and d changes from frame to frame with
   the terrain under the look (crests): the eye lagged and stepped by up to metres. `eye=-,-,-` in the first 24
   trace frames: the camera mode probe was running (the driver skipped its samples), gone with item 2.
4. **Smooth automated moves** (`pm_flight` "Eye space" / "The game's camera model"):
   - the solver walks the look ray to the game's centre surface (`F.centreZ`), takes the distance from the eye to
     the meeting point and sends `F.pitchFor(elevation, distance)`: exact for the camera model in the same frame,
     no lag (feed-forward);
   - closed loop on the model's residual only: each frame's sample (`getEye` over `getCenter` minus the pitch
     read, less the model's offset at the distance / pitch read) feeds a critically damped follower (~3 s, within
     +-0.12 rad, `F.resUpdate`): it starts and stops smoothly, a residual flipping with the terrain every few
     frames moves it by under 0.01 rad;
   - the flattest look bound (no pitch >= 0 shows less than `k(d) pi/2`) comes from the plan's distance (the
     eye's height over its reference ground, x1.15), not the terrain's, so a too-flat plan is steepened as
     smoothly as the plan; a look still too flat where it met the ground is searched once more;
   - a jump of the meeting point (more than 2 m + 2 % against the last two frames' trend: a crest starts or stops
     hiding the ground) is blended over 0.5 s from where the last centre stood (eased; a point the game can't show
     is pulled towards the meeting point): any model error is `d x error`, so a jump of d would step the eye;
   - the Wander's angle range is in the game's pitch now (as the tour's angle rows and the manual wander's current
     view): its eye goes where the game shows that pitch at that distance, so its look is always one the game can
     show (an eye-level wander planned elevations the game can't show, and its look jumped with the terrain);
   - (3) of the request (a centre that doesn't slide over rough ground): with the model applied per frame the eye
     no longer depends on where the centre lands; the centre stays the look's meeting point (a look aimed at a
     smooth path), jumps blended; (4) rate-limiting the distance sent: done only at jumps (the blend), since a
     rate limit in normal motion would pull the look off the plan.
   - Offline (test_flight replays: a synthetic game 0.01-0.016 rad off the model over bumpy terrain, 90 s Wander at
     three angle ranges, a tour glide + Ken Burns hold): the eye's second difference at most 0.08-0.16 m (Wander)
     and 0.35 m (glide) a frame above the plan's own; round 8's way on the same replays 0.46-1.89 m (Wander) and
     1.0 m (glide); with the game exactly as the model, exactly the plan's. Height reads: mean 3.3-3.6 a
     frame, 14 at most.
5. **Diagnostics.** `cam trace` lines now carry `model=` (the camera model's offset at the read) and `res=` (the
   residual estimate) instead of `off=`; every Wander is traced (first 40 frames, then 5-frame bursts at frames
   600, 1800, 3600); the first two moves of a session as before. `eye check` lines carry `model=` and `res=`.
   New `eye smoothness (<hop|flight|wander|tour total|wander total>): frames= d2 max= rms= m acc max= m/s2 jerk
   max= rms= m/s2 per frame worst f= speed max=` (getEye's second difference, its acceleration and the change of
   that acceleration frame to frame): one per hop, flight leg, 30 s of wander and the move's total. `camera
   model: first sample offset ... model ... residual ...` once a session.

## Rev 1 feedback round 10 (built in code 2026-10-13, untested: TESTING.md W1-W9)

From session `2026-10-13_1915_session` (Wander r 800 and r 80, a Wander tour, an Aerials tour of three legs, the
footer's Camera mode twice, the Light tab) and three requests. Nothing here calls setAppConfig or opens / closes a
window.

1. **Hover and money floaters during tours** (user screenshot: the white hover outline on a building during Aerials;
   "$1,194" floaters; "Hide labels and hover" doesn't stop the hover; the log has `hover off (automated camera
   move)`). Cause (read from the game files, findings gui.md "The default selector is the default tool's action"):
   the hover, entity tooltips, click-to-select and the HUD icon config (labels, `showIncome` / `showCosts`) are one
   action, the default tool's (`view_manager.tl` EntityDetailsTool -> `setDefaultSelectorAction`), rendered by the
   tool stack through `useAction`; a fresh one (allowed, re-reading the filter) is built at every un-shelve, and
   whether a plugin's `fireEvent(nil, "preventReactSelector")` reaches it at all is unverified; the sessions say it
   doesn't hold. Our hidden filter does set `showIncome` / `showCosts` false, but the selector only reads it when it
   renders, so the floaters prove it never re-rendered. Fix (the lead from the main session, checked against
   `builtin.lua` ToolStack 1149-1440): our own tool `SquarePhotoModeView` (`react.RegisterTool`, empty push / pop, no
   action) pushed with stacking on the default tool stack while a tour, Wander or Orbit runs, while "Hide labels and
   hover" is on and in the smooth camera. The top tool owns the renderer's action; ours has none, so the default
   selector (hover, tooltips, selection, its HUD icons and floaters) is shelved, as during the game's free camera.
   The normal camera keeps its native controls and our setCameraData. Popped when nothing needs it (the default
   tool comes back with a fresh selector and the player's filter); the pause menu and a new game drop it; another
   tool pushed without stacking clears the stack and runs our pop handler: logged `view tool: removed by another
   tool`, not pushed again until the need ends. The prevent / allow events stay as a second path. Inferred: whether
   the HUD icons (labels) also disappear with our tool on top (then "Hide labels during tours" off still shows none
   during a tour): W1c. The free camera push used `{}` as params where the base passes `{ gameCtx = gameCtx }`:
   `FreeCamTool.push` reads only `cockpitCameraForEntity` and `FreeCamOptions` gets its game context from its own
   recipe param, so `{}` is fine (no change).
2. **Smooth camera** (user: "can camera mode use the freeform camera the game uses", "build the smooth camera idea
   into this app ... we have to make sure you can move around"). The free camera can't be moved by a mod (no
   setter, findings), so the footer now has two buttons: **Smooth camera** (new) and **Free camera** (the old
   Camera mode: the game's own, Esc returns). The smooth camera (`pm_flight` "Smooth camera", `D.toggleSmoothCam`)
   runs on the normal camera with the window and UI root hidden and our tool pushed (no hover): each frame the
   player's step is `getCameraData` minus the view we set last frame (the game applies its keys, edge scroll, drag
   and wheel to it), added to a target; the view shown follows the target with critically damped followers (pan,
   turn, tilt; time scales Low 0.15 / 0.12, Medium 0.35 / 0.30, High 0.70 / 0.60 s). **Zoom passes straight through**:
   the game already eases the wheel towards its own hidden target distance (findings "Camera zoom limit"), so
   integrating its steps would overshoot and a second ease would double the lag; a zoom's centre move (towards the
   cursor) goes through in the same frame. **Level zoom** (checkbox): the target is the eye's elevation instead of
   the pitch, so zooming keeps the angle the land is seen at (the eye flies straight along the look); a tilt changes
   it by dp (1 - k1(d)). Esc opens the pause menu (seen with the UI root hidden in this session), which ends it; the
   pause key too (escape hatch); every game start resets it. The "smooth trace" lines (first 120 frames, then frames
   with input, 600 a session) log read / sent / the step / target / set, to see whether the game also eases pan or
   turn (steps going on after a key is let go: then that channel should pass through like the zoom). Camera tab:
   a "Smooth camera" section with Smoothing Low / Medium / High and Level zoom. What a mod can read (findings
   gui.md "What camera input a mod can read"): only the input's effect on the camera, the mouse's terrain point and
   mouse events over own components; a free look without a button is not possible on the normal camera.
3. **Aerials still jerky; the refit.** The k(d) fit covered d 30-400 m; flights and the r 800 m Wander ran at
   320-1700 m (`camera model: first sample offset +0.463, model +0.577, residual -0.114 (d=810)`; the residual even
   depended on the pitch). Refitted on 106 distinct samples of both sessions (d 25-1725 m): e = p + k1(d)(pi/2 - p)
   + k2(d), k1 = 0.07092 + 0.01624 ln d, k2 = 0.44961 d / (d + 1185): rms 0.0013 rad, max 0.0041 (round 9's 0.018 /
   0.043; other forms compared in findings map-camera.md "Refit"). And the trace showed the game's centre sinking to
   the water level far out: z = 4 + max(g, 0) S(d), S a smoothstep 1 at 800 m -> 0 at 1500 m (120 frames, rms 0.19
   m). The jerk sources, reproduced offline with that game (test_flight replays): (a) the new-area glide of each
   Aerials leg (4.3-4.7 km, its mid-way rise taking d to ~1600-2000 m): round 9 put the eye ~300 m below the plan and
   its residual follower (clamped at 0.12) chased that, with a 26 m second-difference spike (the game's leg 2: 25.7
   m); now 0.02 m; (b) the flight leg itself (d 450-550, the look at the flattest the game can show): 0.74 -> 0.006
   m; (c) the r 800 m eye-level Wander: several metres -> under 0.5 m; (d) inferred, the single 1 km spike of leg 3:
   a frame sent at pitch 0 although the look was flatter than the game can show there (the eye then lifts by d x the
   gap); a last-resort bisection now brings the centre closer along the look instead (`guarded=` counts those
   frames). Built: the model and the centre surface in `pm_flight` (`camK` -> k1, k2; `centreZ(g, d)` used by the
   solver's ray search, `poseOf`, `elevView`, `gameView`, `eyeOf`), the residual follower within +-0.04 and from 0
   for every move (a residual measured at another distance says little: the last Wander of the session started with
   -0.058 left from the flights), every pitch sent capped at an eye elevation of 1.50 (`pitchMaxAt`; it also
   explains round 7's inverted keys: 1.45 at 900 m is 1.67, past straight down; Bird's eye 1.30 at 900 m is now sent
   as ~1.25). Waypoint replans, height lift steps and look-target switches showed nothing in the replays (the
   flight's waypoints are planned per leg; the lift stays 0 at drone height). The smoothness metric: an eye faster
   than 8 km/s (no glide comes near; the session's peaked at 2.3 km/s) or `F.smoothCut` restarts the chain and is
   counted (`cuts=`), so "d2 max=1016 m speed max=48 km/s"-style numbers can't come from a jump again; real jerks
   still count.

## Round 11 camera fixes (built in code 2026-10-14, untested: TESTING.md Z1-Z8)

From session `2026-10-14_0055_session` (smooth camera twice, Hide labels, screenshots 1x / 4x / 1x / 2x, one Aerials
tour) and five requests. Nothing here calls setAppConfig or opens / closes a window.

1. **Smooth camera jumps at the first key press** ("jumps when first pressing a direction, then smooths out").
   Cause (smooth trace f=19-25, findings map-camera.md "Smooth camera: the game draws a key's step before a mod can
   correct it", inferred, strong): `read = sent + step` exactly, and the frame the player sees is the read one: the
   game applies the key's whole step (37-43 m at d 799, ~1.2 x the distance per second) to the view we set last
   frame and draws it before our onStep sets the eased view (which moved 1, 3, 6, 9 m). So the first frame shows
   the game's full step, then the eased view under the next steps looks like a stall (7, 2, 2 m): the jump. Not a dt
   spike, a lastSet mismatch or a game acceleration (the steps have no ramp, read = sent + step at every frame,
   nothing goes on after the key is let go). **Not fixed in code**: no mod code runs between the game's input and
   that frame, no key state is readable, and offline every follower variant (an initial velocity, a predicted step)
   keeps a dip or adds a backward flicker (the same one-frame error shows when the key is let go). The only lever
   found: the game's keyboard camera speed (`keyboardCameraSpeedGame`, settings Keyboard tab) lowered while the
   smooth camera runs, with our steps scaled back up; open questions (does a runtime setAppConfig apply at once,
   its speed curve, mouse-drag steps must not be scaled, the value must never be saved) make it a decision for the
   user. Offline model of the cause: test_flight "round 11: smooth camera start".
2. **Right click ends the smooth camera.** Our view tool now has an action (item 3) whose `ActionDescriptor.onBack`
   is the action's back (the construction menu's right-click abort uses it, `construction_react_util.tl:1416`; with
   the game's default "Back With Right-Click"): pm_hud `H.onBack` -> the plugin -> `D.stopMoves("right click")`
   (smooth camera, tour, Wander, Orbit; a follow stays); with only the labels hidden it logs `back (right click):
   nothing to end`. Inferred (the C++ side isn't readable; whether a right drag that turns the camera also counts
   is unknown): Z2. The tooltip and the Camera tab note say "Esc or a right click brings the interface back"
   (13 languages).
3. **Hide labels and hover still showed the hover** (white outline). Cause (log, findings gui.md "A pushed tool with
   no action leaves the hover and click-to-select on", verified): round 10's tool was on top and a click still
   selected (`Selected entity 32615` at 00:58:09 in the smooth camera, `38215` at 00:58:55 with labels hidden); the
   entity window that opened cleared the stack and popped our tool. A tool with no action doesn't replace the
   default selector's. The base tools that drop the hover (music player, calendar editor, pause menu) give theirs an
   empty `builtin.ActionDescriptor{ tool = "...", children = {} }`. Fix: our tool's push sets such an action
   (`tool = "sqpm-view"`, no Selector, `onBack`), with a `HudIconManagerConfig` built as the base selector builds it
   from the HUD filter (pm_core `hudPreFilter`, the base default lists from `selector_react_util`), so labels and
   money floaters follow the filter: hidden while "Hide labels" is on (the action is set again with a new key when
   the filter changes), the player's otherwise. A missing base piece drops only the icon config (logged once). No
   notification cache (the game context isn't reachable; the toolbox skips it when nil). Inferred: Z1, Z3. The
   checkbox's wording stays (it is what the fix targets); if Z1 fails again, reword it ("Hide labels", the tooltip
   saying the hover may still show; Free camera has none).
4. **4x screenshot: say it takes long.** The log shows `takeScreenshot` blocks until the file is written (the
   game's `Screenshot: wrote` before our line logged after the call): 4x ~11 s with two "Possible hang detected",
   2x ~3 s, 1x under a second (findings map-camera.md "Screenshots" update). A status set in the same frame never
   showed before the freeze ("Saving the screenshot..." appeared after it). Now a 2x / 4x press first announces
   ("Saving the 4x screenshot: the game freezes for 10 seconds or more." / 2x "for a few seconds"), the shot goes
   `pm_shutter.ANNOUNCE_MS` (300 ms) later from the step, and after the call the status says the file is in the
   screenshots folder; the log line adds `call ms=` (the freeze). Tooltips: 2x "The game freezes for a few seconds
   while it saves.", 4x "... for 10 seconds or more ...". The cooldown stays: it is counted from the first tick after
   the call, i.e. after the freeze (seen: written :37, cooldown over :49).
5. **Aerials: no slow-down at the jumps.** Before: the glide to a flight's start arrived at rest and the drone then
   ramped in over 6 s; a leg ramped out to rest before the next glide. Now (pm_flight "flight", `F.newHop` moving
   ends): the drone's clock starts with the glide, which blends onto the moving drone (its ramp, now as long as the
   glide, 4.5 s, ends as the glide lands); a leg no longer ramps out: the next glide leaves the still flying drone
   (`S.leaving` = the flight as a moving hop end), and a leg after a leg flies at cruise from its first metre. Such
   glides use the quintic smootherstep (`cam.ease5`: no step in acceleration at either end) and run in eye space
   (the flight's own elevations; a static end converted exactly with `elevInPlace` = `F.elevView`): the game's-pitch
   form of a flight view is only about the same eye (a ~10 m step at the hand-over in the test). New Aerials areas
   prefer one ahead of the drone and the new leg heads on in the glide's direction (no turn back through a stop).
   Mixed: a hop leaving a flight leg glides from the flying drone too. Tests: test_driver "from leg to leg the
   speed never dips" (min > 70 % of cruise, the hand-over frames' acceleration < 20 % of the glide's peak) and "the
   first glide arrives on the drone at speed"; test_flight "a hop between two moving ends".

## Round 12 camera (built in code 2026-10-14, untested: TESTING.md CA1-CA7)

From session `2026-10-14_0229_sqrl-sqst` (Hide labels on all session, Free camera three times, 2x screenshots, two
Aerials tours; the previous `2026-10-14_0055_session` for comparison) and two requests. Files: `gui/pm_driver.lua`,
`gui/pm_hud.lua`, `pm_flight.lua`, new `gui/pm_cutscene.lua` and `content/mission/keyframes[/en]/sqpm_flight.lua`,
the plugin's one hook line, the Smooth camera tooltip; new DEV mod `mods/square_photo_mode_dev` (never uploaded).
Nothing here calls setAppConfig or opens / closes a window.

1. **Smooth camera: click a point to glide there** (user: "Smooth camera still jitters when you first press. If we
   can't solve, maybe a point to click would be better?"). The key-press jump stays (round 11: the game draws its
   key step before mod code runs). New: while the smooth camera runs, our view tool's action has a
   `builtin.Selector` whose filter accepts no entity (no hover outline, nothing selected); a left click (its
   `onSelect` or `onSelectNothing`, both taken, logged which) reads the terrain point (the click's World details,
   else `api.gui.mouse.getTerrainPosition()`) and `D.smoothClick` glides the view to centre on it, keeping distance,
   angle and pitch: a tour hop in eye space (`F.newHop` with the smootherstep, half the usual mid-way rise;
   `F.clickGlideSeconds`: 1.2 s + 0.45 ln(1 + dist / 100 m), at most 3.5 s), so the eye's path never follows the
   terrain under the moving centre. Keys, drag and wheel keep working: camera input during a glide ends it where it
   is and the smooth camera goes on from there; after the glide the eased controls are back. Log: `smooth camera:
   glide to x,y (click onSelect|onSelectNothing) dist= in s rise=`, `glide arrived` / `glide ended by the camera
   input (why)`, an `eye smoothness (glide)` line. Tooltip (13 languages): "The normal camera without the interface:
   click a point to glide there, or move with the game's controls and the view glides after them. No hover over the
   map. Esc or a right click brings the interface back." Inferred: which callback a bare-terrain click fires with a
   filter that accepts nothing (CA1).
   **The keyboard-speed lever (round 11) is skipped**: lowering `keyboardCameraSpeedGame` with setAppConfig while
   the smooth camera runs could not be kept out of the settings file. setAppConfig only changes the config in
   memory, but every settings save writes the whole config: the game saves at every game start, the settings page
   and other mods call `saveAppConfig` at any moment (findings map-camera.md "Graphics settings from a mod"), and
   this very session saved twice while Photo Mode's own High graphics were on (`Saved settings to settings.lua` at
   02:46:36 and 02:46:40). A crash or quit at such a moment would leave the player's keyboard camera slowed for good.
   High graphics accepts that risk with a restore marker; a camera speed the player set by hand doesn't justify it.
2. **Tours: the hover and the cursor** (user: "don't use the free camera, so you can see the mouse and get hover").
   (a) Cause (log): our view tool was NOT on during either tour. `view tool: removed by another tool` at 02:50:33
   (what removed it isn't logged: no `Selected entity` then; the window had just been closed) set the refusal
   "until the need ends", and "Hide labels" stayed on all session (02:46:39 on, never shown), so the need never
   ended: the tours at 02:56:28 and 02:56:51 logged `hover off (automated camera move)` but no `view tool on`, and
   the game's selector was live (`Selected entity 2` four times at 02:51-02:52). The same in `2026-10-14_0055`
   after 00:58:55. Whether round 11's empty action stops the hover is still unseen in a tour; with labels hidden
   from 02:46:39 to 02:50:33 no `Selected entity` appeared (weak evidence that it works). Fix (`pm_hud` syncTool
   `fresh`): every new request (a move starting, the smooth camera, hiding the labels: the player used one of our
   controls) clears the refusal and pushes again; the tour line says `view tool on` / `view tool OFF`.
   (b) The cursor: the base has a "None" cursor (`gui_react_util.tl`, 1009) and actions carry their cursor
   (`mouseCursor` on the ActionDescriptor, as the construction and line tools do): our action sets it while a tour
   hides the UI (not in the smooth camera: the player clicks there). Inferred (CA2).
   Kept in reserve if CA2 still shows hover: the base cutscene task's `api.gui.fireReactEvent("disableToolActions",
   true)` (the tool stack's `setActionsDisabled`: the renderer gets no action at all) for tours with labels hidden;
   not used now so CA2 tests one change, and because it would also drop the labels a tour may keep.
3. **Tours jerky over terrain: the traces.** The session's numbers (tour 1, a flight leg: 645 frames, d2 max 5.3 m
   at f=624, top speed 131 m/s; tour 2 leg 1: d2 max 24.9 m at f=394 with a top speed of 789 m/s for a 32 m/s
   drone; leg 2: d2 max 56.3 m, 3407 m/s, its 3.2 km new-area glide peaks near 1.3 km/s by plan). Every traced
   frame (the first 40 of each tour) matched the model: `res=-0.000`, the planned eye 0.2-1.5 m ahead of the engine's
   (one frame of motion), and the eye checks within 0.05-0.22 m (d 216-469 m, p 0.006-0.272: no dependence on
   distance or pitch visible). So the jerks are single frames outside the traces where the eye leaves its path by
   tens of metres and comes back. Offline (test_flight "round 12: over ridges") the solver keeps the model's eye
   within 1 m of the plan over 80 m ridges even when the look is flatter than the game can show (the 9 reads a frame
   of the 02:57:00 eye check: the second search); a look floor tried against that case changed nothing and was
   dropped. Inferred: the game leaves the model in those frames (its centre height, a clamp, frame order); not
   fixable blind. Built: an `eye spike` report (`EYE_SPIKE_M` 1.5 m, 12 a session): the frame's engine eye against
   the model's eye for the view read, the engine's centre against the model's centre height, the look's second
   difference, and the solver state of the 4 frames before (planned eye, view sent and whether `setCam` would clamp
   it, ground, the look's leftover, a blend, the clearance lift, guarded frames, height reads). The smoothness lines
   add `look d2 max` (the look direction's second difference: a jolt of the view that the eye's d2 misses).
   CA5 brings the data.
4. **Cutscenes re-evaluated: a DEV prototype.** Facts (findings environment.md "Cutscenes from a mod", from the T9
   probe's log): the keyframe file is loaded and its `data()` runs again at every `playCutscene`, its chunk name is
   its absolute path, `print` works there, `api` / `log` / `ug_require` are nil. So keys could be dynamic if the
   GUI state can write a file and the keyframe state can read it (`io`, unknown in both). The free camera still has
   no setter (`gui.d.tl` Camera: setCameraData / setManualCamera / focusPosition / focusEntity / followEntity /
   enterFollowCameraCockpit; the free camera ignores the first, the others follow entities); a keyframe
   `attachment` follows an entity too, and a mod can't move an invisible entity along a path each frame, so neither
   gives a free path. Built behind the DEV mod `square_photo_mode_dev` (presence marker; nothing changes for
   players): an Aerials tour start plays one straight 20 s flight (40 m/s, one altitude 180 m above the highest
   ground on its path: terrain-free; looking 0.35 rad down) as a cutscene: `pm_cutscene` writes the keys to
   `sqpm_cutscene_keys.txt` next to the mod folder (staging_area; TMPDIR as a fallback), fires
   `disableToolActions` as the base cutscene task does, plays `sqpm_flight.lua`, measures the engine eye
   (`eye smoothness (cutscene)`), restores the game speed and tool actions at the end. Log: `cutscene: GUI state
   io=... os=... load=...`, the file's own `[PhotoMode] cutscene file: data() io=... path=...` and `N keys from ...`
   or `fallback still frame: why`, `cutscene flight: ... playing` / `NOT played: why`, `cutscene flight end after
   N s (played|never playing|timeout)`. If it plays smoothly, tours could be built from keys (open: player input
   ending a cutscene early, 2 of 5 T9 runs; a tour longer than one cutscene; the keys' `speed` field; the fovY that
   matches the normal camera). If either state lacks `io`: record it, the path is closed.

## Round 21 (built in code 2026-10-14, untested: TESTING.md R21-1..R21-4)

User (2026-10-14): "aerials high mode isn't working. never goes very high. a lot of times when starting aerials
its cut off the bottom of the map"; "make sure no extra settings other than debug mode are in mod settings".

- **Cause (session `2026-10-14_2332_r20-test`, sub-arctic map, DEV mod on):** every Aerials Start with the DEV
  mod played the DEV cutscene flight (`D.toggleTour` -> `cutsceneFly`, 29 `cutscene fly plan` lines), whose keys
  fly `C.FLY.height` 250 m over the anchors whatever the Look; High was never flown. Five of those flights logged
  `cutscene fly NOT attached: eye 5350 m from the plan`, all from the fallback plan from the view's centre over
  the same first anchor 47716 (MODEL_INSTANCE_LIST at -1752,-5078): the eye sat at the world's origin, not
  above the plan (the "cut off" view); the next Start picked the same anchor again.
- **Fix:** the High look never plays the cutscene flight (logged `cutscene fly skipped`), it flies the scripted
  High flight (`pm_flight.highPose`, ~1 km up); Down / Horizon keep the DEV cutscene flight. An anchor whose
  flight did not attach is left out of every later plan this session (`pm_driver` `flyFind`, at most 64).
  Without the DEV mod nothing changes: Aerials was always the scripted flight.
- **Mod settings:** `hudButtonStyle` removed (the button section above: "Always the icon"); only `sqperf_log` stays.

## Round 20 (built in code 2026-10-14, untested: TESTING.md R20-1..R20-9)

From session `2026-10-14_2150_r19-test` (High graphics' 6 stages twice, no crash; 28 lens plays, 1 refusal; every
cougar click refused with "noise 60") and the user's notes.

1. **Risky graphics removed** (user: "why do we still have geometry, terrain, grass in risky graphics. lets remove
   risky graphics and have those 3 in default high graphics"). `square_photo_mode_dev/content/photo_mode_dev/
   pm_risky.lua`, its hooks (`pm_cutscene.devRisky`, the plugin's start / step / pause menu, the Settings rows) and
   `tests/square_photo_mode/test_risky.lua` are gone; no marker of it is left in the user's settings (its last
   pause menu cleared it). High graphics mode raises geometry, terrain and grass (pm_core STAGES 4-6, one key each).
   A note under the Settings tab's options: "Shadows can't be changed while playing: it crashes the game. Set
   them in the game's Settings menu (Graphics)." The risky test left the player's own geometry / terrain / grass at
   High in settings.lua (the start recovery read them as changed since).
2. **Animals tab** (user: "add a new tab for animals. add more options of things to insert, interesting ways to
   insert, etc. try to make sure when inserted you can see them ... add note about animals dying immediately in
   wrong zones. cougar keeps saying no place these animals can live, even on flat. we should allow putting wrong
   animals in environment even if they die right away, just note that"). The eighth tab (the construction menu's
   paw, `category_landscaping_animals`; every tab icon 16 px so eight fit: docs/ui-guide.md "Windows"):
   - **More to insert**: every group in every climate (the climate's own first; another climate's says so in its
     tooltip and the status), new: lone deer, two bears, and the draft horse (lone, pair, herd of 5-9): its model
     is an animal with every suitableAreas value 0, so it lives anywhere (findings scripting.md). Discus schools take
     one of the four discus models at random.
   - **Ways to insert**: Distance (Close / Middle / Far: each animal about 12 / 6 / 3 % of the screen high),
     Formation (Group, Line across, Single file, Spread out over the width), Facing (Any way, To the camera,
     Side-on, Away; the spawn command's lookAt).
   - **Visible**: rays through a 5 x 7 grid of screen points (`screen2World` depth 0 / 1) are marched onto the
     terrain (`M.march`: growing steps from 2 m, x1.12, then 8 halvings; at most 80 steps, 6 km), each hit projected
     back with the animal's height (a bird's at its flying height); the hit nearest the chosen on-screen height,
     near the frame's middle, is the group's middle; every member must project inside the screen (4 % margin).
     Land animals never on water, fish only on water. A view with no ground is the one refusal ("tilt the camera
     down"); a best spot far smaller than asked says "bring the camera lower or closer".
   - **Never refused for the score**: the score adds `BAD_SPOT` (0.7) to a spot's cost, so a suitable spot wins when
     it frames about as well; otherwise the animals go where asked and the status says they may die within seconds.
     The tab's last line notes it for every animal.
   - "Remove the added ones" is "Remove all"; the per-species list and its Remove stay.
3. **Saved views description** (user: "saved views needs a description of what it does"): a line under the
   heading: save views, jump with Go or tour them (tick Saved views in the Tour tab), in list order.
4. **A jump follows** (user: "jump to subject should auto follow"): a jump to a vehicle or person (the subject's
   `follow`) starts the follow at the framed view, as the fastest vehicle did; the photographer's framings
   (`s.framing`: bridge, tunnel portal, approach ...) wait at their spot and stay still. The Follow toggle shows it
   (its tooltip says so); a click ends it.
5. **Slower subject orbit** (user: "orbit on subject should be slower"): the orbit cutscene turns in 48 s, not 24
   (`C.ORBIT.seconds` and both `sqpm_orbit.lua` copies; 15.7 m/s around a standing subject; the 2150 bus orbit
   ran 18.6-120 m/s, mean 44).
6. **The pause after a cutscene** (user: "game keeps pausing after coming out of cut scenes, even if it was playing
   before"): the end restored the speed correctly, then something paused the game (22:15:46 "speed 1 kept", the
   next play 22:15:51 read 0, and every later end put that 0 back as the player's). Inferred: the skipping Esc
   (findings environment.md "The game pauses again just after a skipped cutscene"). `pm_driver.watchSpeed` after
   every end of ours (lens, orbit, flight): for `SPEED_WATCH_MS` (2.5 s) a speed that is neither the player's nor
   what the end left is put back once and logged with its delay; a play meanwhile takes `D.playerSpeed()` (the
   watched value); the pause menu and a new game end the watch.
7. **Arrow dent gone** (user, R19-5): docs/ui-guide.md "Controls" has the rule (compact contour under ~30 px).
8. **Telephoto looks weird** (user: "telephoto often looks weird in lens view, more so with the looks set. maybe
   unavoidable"): the lens kept the player's frame height, so 135 mm stood 3.6 km out on a 513 m view (2150), 400
   mm 5.3 km. From there the subject sits behind kilometres of haze (the looks raise it up to x10) and models show
   their far LODs (picked by metres, not zoom). Neither can be cut per shot; `L.FAR_D` (1.5 km) now narrows the
   player's size bucket until the eye stands within it, and a wider size step past it gives no plan. So a long lens
   frames tighter, as a telephoto does (findings environment.md "A telephoto from kilometres out").

## Round 19 (built in code 2026-10-14, untested: TESTING.md R19-1..R19-5)

From session `2026-10-14_2019_r18-test` (PhotoMode 805 lines: 11 lens plays, 24 refusals, 64 gulls then "not
added") and the user's R18 results: R18-5 the vehicle stays centred but "feels fairly jerky"; R18-6 the lens
"doesn't want to start ... on ordinary landscape"; R18-2 "arrows look better, still small divet on left".

1. **Animals: no limit** (user: "why say thats enough animals for now. lets keep a list on animal count and allow
   people to add as many as they want"). `M.MAX_ADDED` (64) and its status are gone; a click still adds at most
   `PER_PRESS` (20). The Subjects tab lists the added ones still there per species ("Added here: N animals",
   then a row per species with "Remove N", which removes only that species); "Remove the added ones" stays. The
   life checks run in slices of `LIFE_PER_STEP` (40) a frame, round robin, so hundreds cost the same per frame;
   a death drops out of the counts. Save impact unchanged (base animals, saved with the game).
2. **Orbit with super telephoto "never works"**. Log: 10 of 24 refusals were "the lens camera would stand off the
   map (5333 m out)": 400 mm keeping the player's ~800 m frame stands 5.3 km back, and an orbit needs that room on
   every side of a ~8 km map. `L.choose` takes a size bucket step (`opts.ds`, `L.SIZE_SHIFTS` 0, -1, +1, -2, ...):
   `pm_lens.prepare` tries the tighter / wider sizes over the widest search's candidates when the player's own
   size gives no shot. Tighter halves the distance per step, so a 400 mm orbit plays at 1.3-2.7 km ("Framed
   tighter so the lens camera stays on the map").
3. **Lens on a vehicle: easing** (answer: none possible). The key fields have no smoothing field and the locks
   keep only the look in world axes (findings environment.md "A cutscene camera follows its anchor rigidly"), so
   the camera is rigid on its carriage; a long lens magnifies every bump. New Camera tab row "Vehicle": Ride along
   (the default, as before) / Steady (the followed vehicle is left out of the anchors: a static one beside its
   way, the vehicle crossing the frame); the lens tour follows the same choice.
4. **Lens on ordinary landscape**. The other 14 refusals: the best anchor put the player's centre 21-169 % of the
   frame off its middle. Now (a) wider size buckets halve that per step ("Framed wider ..."), and (b) when no size
   gets within `L.ACCEPT` (20 %), the best shot within `L.ACCEPT_ANY` (one frame height) plays anyway, centred on
   the nearest object ("No object at the middle of your view: the lens looks at the nearest one"). Nothing plays
   only with no anchor within 1 km or nothing within a frame height. Not chosen: spawning an invisible anchor
   (anything spawned is saved with the game) and trees as anchors (multi-instance groups, findings).
5. **The notch on the arrow buttons**: the step buttons still drew the default 30 px contour (9 px corners) on a
   24 x 28 px button. They now set the base's small-button contour inline (`compact_contour` / `compact_surface`,
   5 px corners, as the base TextInputField; `pm_window.compactStyle`), the `secondary` class still colouring it.
   No stylesheet rule (`make css-rules` unchanged).

Strings: 21 new keys, 1 removed, all 13 languages. Tests: test_animals (no cap, counts, per-species remove, the
life slice), test_lens (size steps, off-map tighter for hold and orbit, wider / nearest, Steady).

## Round 18 (built in code 2026-10-14, untested: TESTING.md R18-1..R18-7)

From session `2026-10-14_1729_add-money-100m` (PhotoMode 729 lines: 33 lens plays, 17 refusals, a DEV flight with
four F9 screenshots) and seven user items (plus two coordinator changes).

1. **DEV: risky graphics** (user: "separate checkboxes to toggle the other graphics settings that were crashing
   earlier, just as a test"). In the DEV mod only (`square_photo_mode_dev/content/photo_mode_dev/pm_risky.lua`,
   English text, exempt from translations): Photo Mode's Settings tab appends its rows when `pm_cutscene.devRisky`
   loads it (the DEV presence marker). A checkbox per key (shadowQuality, geometryQuality, terrainQuality,
   grassQuality) sets that key to 2; each change is one `setAppConfig` with only that key, queued to the plugin's
   onStep (one per frame, never while High graphics mode stages / restores or the window opens / closes), with a
   log line right before ("setting a -> b ALONE ...; a crash right after this line is this key") and after. The
   player's values go into `mainMenuState.square_photo_mode_dev` (saved) before the first raise; untick, the pause
   menu (every key, one call each) and the next start after a crash (keys still at 2) put them back. Tests:
   `tests/square_photo_mode/test_risky.lua` (loads the DEV file).
2. **The notch in the "<" / ">" buttons** (user screenshot). Base vs ours: the outlined contour is the base
   `Button` 9-slice (`default_contour`, 30 px, 9 px corners, a ~7 px arc; `Button!secondary` colours it); the
   compact padding (`sqpm-small`, 4 / 6 px) is ours. A one-glyph text button came out barely larger than the two
   corners, so the side edges had no straight middle and the arcs met: the notch (inferred from the texture and
   sizes). The base has arrows: the `DoubleSpinBox`'s +/- buttons draw `::/gui/builtin/spinbox/arrow_left.tga` /
   `arrow_right.tga` in compact-contour buttons (`compact_contour`, 5 px slices). Every Photo Mode step button
   (time / season / sun / cloud sliders, the look arrows) is now our compact icon button with those base arrows
   (`pm_window.arrowButton`, 16 px icon: 24 x 28 px); no new rule. ui-guide "Step a value" updated; findings
   gui.md "The base button contour".
3. **A screenshot button in Lens view** (+ the coordinator: "can we add buttons to cutscenes"). Found in the log:
   F9 (`IA_GAME_SCREENSHOT`, the base FreeCamOptions' input action, `takeScreenshot(2)`) wrote four 2x screenshots
   during the DEV flight cutscene: it works in a cutscene (verified). Buttons: every mod extension point is inside
   the UI root a cutscene hides; FreeCamOptions sits in GameUIProxyRoot outside it, so `gui/pm_bar.res.lua` wraps
   that recipe through the official `react-replacement-config` (as the campaign wraps HudIconMasterGame): the
   original renders unchanged, plus a small bar while `driver.S.cutscene` is set (camera icon, 1x / 2x / 4x through
   the window's shutter, Stop: the lens tour's stop or the stop file). Inline styles, no full-screen element.
   Untested: whether the mouse reaches the bar while the cutscene holds the input (R18-3); F9 is the sure way and
   the Lens notes name it. Caveat: another mod replacing FreeCamOptions too would win or lose (one owner).
4. **Depth of field** (answer only): none exists (findings environment.md "No depth of field"): no env field, api,
   cutscene key or camera-tool setting; the cutscene keys carry fovY only; a long lens compresses the background
   but blurs nothing; the only route is a shader replacement (manual install, PC only). A Lens note now says so.
5. **Super telephoto on a bus "points the camera down"**. The keys had `lockYaw` false, `lockPitch` / `lockRoll`
   true. In the log, a 400 mm hold on a climbing plane checked 15.6 s in: the eye 269 m off the plan and the plane
   3.43 screen heights below the middle; static anchors read +0.00. With the 0842 result (the position turns with
   the anchor's yaw, locked or not) the reading is: the position turns with the anchor's pitch as well, the locked
   look stays level, and at 1.8-9 km out a few degrees of grade swing the eye by hundreds of metres. Chosen: every
   lock false (the camera rigid in the anchor's frame, as the 0633 carriage orbit that kept its vehicle in view);
   the vehicle stays centred and the view tilts with the grade (a chase camera). Static anchors leaning over 2
   degrees are skipped (`L.TILT_MAX`, `pm_lens.tiltOf`). Not chosen: shorter distances for vehicles (the tilt is an
   angle: it shows the same at any distance for a given lens) and a static anchor beside the road (the vehicle
   leaves a 400 mm frame in a second or two). 3625 files regenerated.
6. **"Nothing to attach to"** (answer: a key's position needs an anchor: the keyframe file is static, runs without
   api, and the only per-play input is which entities its placeholders map to; the dev console has no `io`
   either). From the log: manual starts played 12 of 29; all 17 refusals had 28-57 anchors near and failed only
   the aim limit (the centre 5-24 % of the frame off the middle; never "nothing within 1 km"); trees count
   (ASSET_GROUP 3-33 with a fat instance per search where trees exist; 0/0 near a vehicle in town = none there);
   constructions never carry a fat instance (CONSTRUCTION 0/48: their parts are counted as MODEL_INSTANCE_LIST).
   Changes: `L.choose` also tries the neighbouring heading (+-15 degrees) and elevation buckets per anchor
   (`L.SHIFTS`), and `L.ACCEPT` 0.05 -> 0.2 (the shot centres the nearest fitting object; the player's centre up
   to a fifth of the frame off the middle). A refusal with anchors near says "No object close enough to the
   middle of the view for this lens ..." (new), the old "nothing to attach" only when none is within 1 km.
7. **Hide labels** (coordinator's revision: keep the checkbox): "Hide labels and hover" renamed "Hide labels" with
   an honest tooltip (names, rates, icons; tooltip and click-to-select off; the outline may still show); behaviour
   unchanged. Tours, Wander, Orbit and the Lens keep turning hover and clicks off while they run (the world lock);
   the Tour tab's "Hide labels during tours" stays. Normal (non-DEV) Aerials still use the normal camera; only the
   DEV mod plays cutscene flights.

Strings: 7 new keys, 2 removed, all 13 languages. CSS: no new rule. Findings: environment.md (F9 in a cutscene,
pitch, dev console `io`, the second-play note), gui.md (recipe replacement, the button contour), map-camera.md
(the DEV retest).

## Round 17: lens, animals, orbit (built in code 2026-10-14, untested: TESTING.md LA1-LA8, LT1-LT6, AG1-AG6, OR1-OR3)

From session `2026-10-14_0842_session` (desert map) and the user's notes: "a whole herd of elk, flocks of birds, a
lone cougar"; "prevent animals dying immediately on spawn"; "Look through the lens doesn't do anything, how do I
test?"; "Can we make it work on empty landscape?"; "one line, not wrapped"; "Does Orbit always orbit the same
thing now?"; "it doesn't look where I'm pointing, seems random"; "it bumps me out"; "I would prefer to cancel
myself"; "an option for pause/speed"; "a Look through the lens mode where it jumps between scenes every 10
seconds"; "Dust looks bad and too subtle, get rid of it".

1. **Lens aim** (`pm_lensdef`, `pm_lens`). Evidence (findings environment.md "Cutscene attachments"): with all locks
   true the key's position turned with the static anchor's yaw (the turned reading 0-37 m, the world one 7-1703 m)
   but the look stayed in world axes: the fov measured on the anchor was the file's times cos(yaw) (phi 71 / 77.5
   deg for yaws 71.6 / 78.1): the camera looked past the subject by the anchor's yaw, the "random" look. And the
   round 16b check (world axes, 25 m) stopped attached shots ("bumps me out"). Now: lockYaw false (pitch / roll
   locked), the heading bucket picked in the anchor's frame (the player's heading minus the yaw), 24 headings (15
   deg) x 5 elevations (5 / 12 / 20 / 30 / 45): 3625 files, 4.6 MB. The files look at their anchor, so the view's
   centre IS the anchor; `L.choose` takes, among the candidates (the followed / jumped-to vehicle's carriage, static
   model entities searched at 30 / 80 / 200 / 500 / 1000 m), the one whose shot puts the player's centre nearest
   its middle (`centreError`: an anchor on the line of sight counts too), and plays only within 5 % of the frame
   height (test: 120 random views through a simulated engine). A view off the map is refused (tele holds 0.4 s in
   ended themselves, inferred: off the map).
   Coordinator's offset-bucket idea (look at a point beside the anchor): every offset needs its own file per lens,
   size, elevation and heading (a 17 x 17 grid = x289, ~1 M files); a world-coordinate key needs the position in
   the file, which has no channel from the GUI. Not built; empty land without an object within 1 km can't play
   (status + tooltip say so, LA5).
2. **No automatic stop** (user): the check at 0.5 s only logs (attached / drifted / NOT attached against the raw
   offsets around the origin) and where the anchor shows on screen; NOT attached puts "press Esc" in the status.
   The DEV cutscene orbit the same. Every end before the check logs its reason.
3. **World** choice (Your speed default / Paused / Normal): set once the play is seen (the cutscene sets 1); 1.5 s in
   the speed read back and the camera's motion are logged; a paused orbit whose camera stands still gets 1 back
   (whether the cutscene clock is game time is open: LA6).
4. **Lens tour**: a new subject every 5 / 10 / 20 s (pm_world.pick over vehicles, trains, ships, aircraft, stations,
   towns, industries, places; not within 400 m of the last 6, not within 300 m of the edge; 8 tries a scene), a lens
   from All / Long / Wide, a view of its own (8-30 deg up, framed per kind), a hold; the next file replaces the
   playing one (0842: a second play replaces). World and Screenshot apply per scene; Esc ends it.
5. **UI**: "Lens view" and "Lens tour" are natural-width buttons (one line in every language, no new CSS rule); the
   button's tooltip leads with the last failure; a note on what the lens looks at.
6. **Animals** (`pm_animals`): 19 group presets of the 10 species (herd of deer 6-12, wolf pack 3-6, lone predators,
   flocks of gulls 8-20, eagles circling 3-5; cranes / salmon / discus are one flock entity each: 1 or 3). No elk
   model exists: the herd is deer (temperate / subarctic). Cause of the deaths (inferred from the wiki and the
   models, findings scripting.md): spots with a negative `suitableAreas` score (cougar: bias 5, slope negative from
   ~0.31; round 16b allowed 0.45). Each land / fish spot is now scored the engine's way from what a GUI script reads
   (height, slope over 8 probes 4 m out, noise in dB, water / shore within 20 m, roads 40 m / buildings 60 m,
   tree groups 30 m, our predators 150 m for deer); >= 0 to place; birds anywhere. Every added animal is checked
   each second for 3 min: its death logged with its lifetime, last `invalidTileElapsed` and the score parts
   (AG3 tells whether the score explains it). `entityExists` before every read (the 0842 "Invalid entity"). Caps 20
   a click, 64 a session.
7. **Orbit** (`pm_driver` D.orbitTarget): Orbit circles the middle of the view unless the followed / jumped-to subject
   is still within max(30 m, 0.15 x the distance) of it; a stale subject is dropped. The DEV cutscene orbit takes a
   static anchor only within 40 m (0842 orbited one 237 m off every time). The status line and the tooltip say what
   it orbits.
8. **Dust removed** (user: bad and too subtle).

## Round 17: interesting views vary (built in code 2026-10-14, untested: TESTING.md IV1)

User: "The interesting buttons should always be able to click through and get a new view each time, even if it's
just a different perspective of the same interesting thing."

Why clicks repeated: every Interesting pick was deterministic. The scans return the best-scoring vehicle of the
part of the fleet they read, and Oldest / Longest keep their best across clicks on purpose, so once found the
same vehicle came back every click; a map with one train on a bridge (one tunnel, one platform...) always gives
that one. Skyline always takes the biggest town and the best ring direction, Viewpoint the best hill of a small
map's towns, Busy street the densest cell. The framing then varied only by `side()` (two sides of the track) or
not at all (skyline, viewpoint, rush, saved views), so half the clicks or all of them landed on the identical
view. (Round 14's shot anchor was not involved: a jump resets it.)

Built (`pm_variety.lua`, pure; `pm_world.lua`, `pm_driver.lua` D.jump):
1. A bag per pick kind: the scans prefer a vehicle (a pair for Trains passing, a ring direction for Skyline, a
   hill for Viewpoint, a cell for Busy street) not shown yet in the kind's cycle; a shown one wins only when
   nothing fresh is found and never stops a scan early. A cycle holds `POOL_MAX` (6) subjects, then the best come
   back. Saved views (Anything, the tour's shots) are a shuffle bag: each once per cycle, never twice in a row.
2. Every pick carries `variant`: how often that subject was shown before. Variant k > 0 keeps the centre and
   turns the heading k golden-angle steps (never the same heading twice), with the distance and pitch of a shot
   style in turn (eye level 0.75 x d at 0.05 rad, high 1.35 x d at p + 0.35 up to 0.85, low 0.95 x d at half the
   pitch) and a +-15 % distance jitter; low views are kept clear of hills (`clear`). Variant 0 is the shot's own
   framing.
3. D.jump never lands on the view of the previous jump (`pm_variety.distinct` steps the variant on).
4. Log: `interesting pick <kind> #n of m, view variant k` (m: the subjects found so far in the cycle, at most 6).

Tests: test_variety (20 clicks on a one-item pool give 20 distinct views; a five-item pool visits all before
repeating), test_world (one-train / five-train bridge pools, skyline directions, saved views shuffled),
test_driver (20 jumps, 20 distinct camera views; the same subject twice in a row).

## Round 16b (built in code 2026-10-14, untested: TESTING.md LN1-LN8, FG1-FG6, AN1-AN6)

User: "Wide or telephoto camera angle -- this is what we've been trying to achieve the whole time. We need to push
this idea."; "What about relocating animals already in the map to within our frame -- can we do that?"; "Add the
items you propose" (Foreground: Low cloud veil, Rain, Dust). Built in new modules with small hooks in shared files:
`pm_driver.lua` (D.step: a cutscene state with its own `step` is stepped by it, 3 lines), `pm_button.script.lua`
(requires, the new-game reset, two step calls, the pause-menu stop), `pm_window.lua` (an `extend(build, module)`
wrapper and a helper table `UI` appending each module's `rows(UI)` to the Subjects / Camera / Weather tabs). No CSS
rule added. Production (not DEV-gated): the Lens is the user's top goal and every path ends by itself; what is
inferred is logged.

1. **Lens** (Camera tab: Lens ComboBox, Move Hold / Orbit, Screenshot None / 1x / 2x / 4x, "Look through the lens").
   The normal camera has no fov; a cutscene key has `fovY` (findings environment.md "Cutscene keys"). The keyframe
   file is static and its `data()` can't read the camera, so every key is attached to placeholder 9999800, mapped at
   play to an entity at the view's centre (the followed / last jumped-to vehicle's carriage within 120 m of it, then
   the nearest static model entity within 60 / 160 m: `pm_world.flyCandidates`); the key's position is the eye
   relative to that anchor, looking back at it (+4 m, the normal camera's centre height). The rest comes from
   buckets, one file each (`pm_lensdef`):
   - lens: 12 / 18 / 50 / 135 / 400 mm (fovY 1.5708 / 1.1760 / 0.4711 / 0.1771 / 0.0600);
   - size: the frame height at the subject, 20-640 m doubling; the player's is 2 d0 tan(30 deg) (the game's 60
     degrees, inferred, measured by world2Screen and logged), the nearest in ratio; D = H / (2 tan(fovY / 2)), so a
     400 mm lens stands ~20 x farther back than the player (compression), a 12 mm one ~0.6 x;
   - elevation 6 / 18 / 40 degrees, the nearest, raised while the line of sight would come within 6 m of the terrain
     (24 samples);
   - heading: 12 (30 degrees apart), the nearest: the view turns around the subject by up to 15 degrees.
   Hold: 2 keys 40 s apart, the eye drifting 3 % of D closer (two equal keys would be a zero-length spline: the
   binary's `result.length > .0f`), speeds the chord over the time. Orbit: one turn (60 s for 12 / 18 mm, 90 for 50,
   150 for 135, 240 for 400) starting at heading 0 (no heading buckets: 87 files instead of 1044). Locks all true
   (world axes, inferred). 5 lenses x sizes within 8-9000 m (29) x 3 elevations x (12 holds + 1 orbit) = **1131 files,
   1.7 MB**, `en/` only (only `en/` is ever loaded), generated by `tools/gen_lens_keyframes.py` from `pm_lensdef.lua`
   through lupa (one source; `--check` reports drift; test_lens checks every 9th file against the module, all with
   TEST_FULL).
   Runtime (`pm_lens`): stops our moves, plays, puts our state on `driver.S.cutscene` (kind "lens", so the world lock
   and hover-off of round 15 hold); 0.5 s in "lens check": the eye against the plan in world axes and turned by the
   anchor's yaw (attached / TURNED / NOT attached: the stop file then ends it); 1 s in "lens fov measured"; at the
   cutscene's 2.5 s the shutter (driver.screenshot, the primer rule included) when a scale is picked: does
   takeScreenshot work with the UI hidden by a cutscene (LN4); at the end (Esc or its end) the player's game speed
   back, tool actions back. Not started (logged, status): a cutscene already playing, no camera read, no anchor.
   Open: the lock semantics (LN3), whether the 60 degrees hold (LN2), anchors of each entity type (LN5).
2. **Foreground** (Weather tab, below Adjust): checkboxes Low cloud veil, Rain, Dust.
   - Veil: cloudBase 30 m under the eye, cloudTop 60 m over it, cloudScattering 0.012, cover at least 0.6, through
     `pm_sky.set` (the override: its untick, the pause menu and the next load put the player's values back); it
     follows the eye (re-set quietly when the eye moved > 40 m, checked once a second); untick: the values back
     when still ours (`restorePlan`, a moved slider is kept); the base moved elsewhere ends it.
   - Rain: cover 0.97 (`rain.fs` fades drops in over 0.8-1.0 and draws them only below cloudBase; the eye's height
     against the cloud base is logged with the read-back). With the veil on as well, the cover comes back to the
     veil's / the player's in either order (tests).
   - Dust: `api.gui.rendering.spawnDust` every 0.7 s, a box (2-30 m, 4 % of the distance) on the ground 15-55 % of
     the way from the camera to the centre, sideways spread; the first 4 puffs and any error logged. **Removed in
     round 17: the user found it bad and too subtle** (findings environment.md "spawnDust").
   Every exit: untick, the pause menu (before pm_sky's own restore), a new game (state dropped).
3. **Animals** (Subjects tab: species ComboBox for the map's climate, "Add to the view", "Remove the added ones").
   Relocating existing animals is not possible: `makeAnimalSetStateCmd` has no position or target (findings
   scripting.md "Animals from a GUI script"). Adding is: `makeAnimalSpawnAtCmd("::/animal/...mdl", pos, lookAt)` per
   animal (the user's console spawn, 2026-10-14), facing the camera, at points sampled in the view (35-110 % of the
   way to the centre, sideways up to 0.35 x the distance): land animals on dry ground, slope <= 0.45, no edge within
   8 m and no construction within 12 m; birds anywhere (they fly at their model's height); fish on water. 1-3 a
   click by species, at most 8 a click and 32 a session; each command's callback (ok, entity) logged and the
   animal's position and movement type read 1.5 s later. "Remove the added ones": `makeCustomEntityDestroyCmd` for
   ours that still exist. Save impact (in the tooltip): ordinary base animals, saved like the game's own and
   despawned by the engine; removing Photo Mode leaves only base animals.

## Round 16 camera (built in code 2026-10-14, untested: TESTING.md CE1-CE6)

From the user's round 15 run and five reports. **Its log is lost**: `2026-10-14_0733_session` was archived at
07:38:29 by a session-start hook while the game ran on (looks at 07:34-07:35, then the user's tours and screenshots
at 07:40-07:51, `screenshots/2026-10-14_00-40..00-51`), and the next game start at 07:53 overwrote `stdout.txt`
before anything archived it again. So none of the round 15 lines (`world lock`, `hand-back`, `cutscene fly ...`)
were read; what follows rests on the code, the DEV mod being on in that session (its mod list) and the reports.
Files: `pm_flight.lua` (`VIEW_MARGIN`, `inner(bounds, margin)`, the recent areas), `gui/pm_cutscene.lua` (turns,
`viewInside`, `routeInside`, `chooseStart`, `chooseNext`), `gui/pm_driver.lua` (the settle, the eased orbit, the
DEV static-anchor orbit, the fly chain), the DEV mod's 40 `sqpm_fly_<h>_<t>.lua` files (x2), `description.html`
(both mods), tests (test_cutscene, test_flight, test_driver). No new player-facing strings.

1. **"Aerial High no longer has the hover issue. Free camera or cutscenes?"** Cutscenes (inferred, strong): with
   `square_photo_mode_dev` on (loaded in 0733), Start in Aerials plays round 15's DEV cutscene chain whatever the
   Look row says (`D.toggleTour`: `cutscene.devOn() and cutsceneFly()` first; the normal tour only when no anchors
   are found). A playing cutscene is a native camera action that takes the map's input, so no hover or clicks.
   The free camera still has no setter (findings map-camera.md "No camera a mod can steer ..."). Also consistent:
   the same place every start (item 3) and the view off the map edge (item 2) are both what the round 15 cutscene
   planner does, not the normal tour. Without the DEV mod players get the normal tour with round 15's world lock
   (CD1 / CD2 still open).
2. **Aerials looks out past the map edge** (user screenshot: the terrain's edge with the sky's gradient beyond;
   findings map-camera.md "Past the map edge ..."). Round 15's cutscene planner kept only the keys' anchors 150 m
   inside the map and flew straight along one heading (6 x 600 m) until a waypoint left it; at 250 m up and 20
   degrees down the frame shows the horizon, so the edge showed from kilometres away. Built:
   - **The DEV flights keep their picture on the map**: `C.viewInside` = the eye `edgeM` (300 m) inside and the
     ground `reach` m out along five rays across the frame's width (+- 0.7 rad) inside; `reach` = 2.5 km, at most
     30 % of the map's smaller side (`C.reachFor`, logged as `view kept N m on the map`). Every anchor is checked
     with its key's heading (`planFly`), and every route before any octree search (`routeInside`, with the anchor
     search radius added).
   - **Flights turn**: one DEV file per heading and turn (`sqpm_fly_<h>_<t + 2>.lua`, t = -2..2: the keys' heading
     goes from h to h + t x 45 degrees evenly over the flight, unwrapped, and the GUI places the anchors along the
     legs' mean headings), so a chained flight starts on the last one's end heading (no snap at the hand-over) and
     can bend up to 90 degrees away from an edge. When no turn keeps the view on the map, the chain cuts to a new
     area (`a cut to a new area`, counted in the end line).
   - **The normal tour** (any look): waypoints and new areas keep `pm_flight.VIEW_MARGIN` from the edges (High /
     Horizon 2.5 km, Down 0.9 km; at most 30 % of the map a side, at least the 12 % inset). Offline: a 300-chain
     sweep on a 10 km map keeps every anchor's view on the map, about one hand-over in three cuts there (test_cutscene
     "round 16: 300 random chains ..."); bigger maps cut less.
3. **"Now Aerials always shows the same place."** Cause (code): `cutsceneFly` started at the view's centre along
   the look (rounded to 8 headings) and `flyNext` kept that heading: the same view gave the same flights. Built:
   the first flight goes over a **place of interest** (`world.flightCandidates`: the Aerials subjects, towns,
   stations, industries, rivers, water, hills, rail) in a weighted random order, with a random heading and turn,
   the place in the flight's middle (`C.chooseStart`, at most 10 places / 6 searched plans); the next flights
   choose the turn whose route passes a place not shown lately, plus randomness and a gentler-turn bonus
   (`C.chooseNext`). **Recent areas** (`pm_flight` `rememberArea` / `nearRecent`: a ring of 16, 1.5 km, kept for
   the game session): each flight's middle and its place, and the normal tour's waypoints and new areas; places
   near one are skipped while others exist (cutscene) or weigh a third / lose 3 points (the tour's waypoints / new
   areas). No place fits: round 15's line from the view's centre (now with the view check). Log: `cutscene fly plan
   (start): over <kind> at x,y, heading h turn t (n interests, m routes, k plans; N areas shown lately avoided);
   map WxH m, view kept R m on the map; anchor search ...`, `cutscene fly plan (lead | after the end): on from the
   last anchor, heading h turn t` or `no way on (...): a cut to a new area`, `cutscene fly i/4 ...: heading h turn
   t ...sqpm_fly_h_k.lua`.
4. **"Orbiting with the nice movement of Aerials?"** Evidence of what is smooth: cutscenes (0606: d2 max 0.72 m;
   the attached orbit 0633: d2 max 1.04 m, its pulse fixed in round 14 by Auto Set Speed, CC3 untested) and the
   High tour (0633: d2 max 0.51 m, jerk rms 6.9 m/s2). The manual Orbit turns around a FIXED centre, so the cause
   of the tours' jolts (a moving centre over terrain, findings "Tour eye jolts from the game's centre") never
   applies to it; what it lacked against the tours is the eased start and end (full speed from the first frame,
   a dead stop at the button). Built: (a) **the manual Orbit eases in** over 1.5 s (smoothstep on the turn
   rate) and the button lets it **ease out** over 1.5 s (`orbit slowing to a stop (button)`, then `orbit off
   (button: slowed to a stop)`; a second press stops at once), with an `eye smoothness (orbit)` line at its end
   (none before: no data on it yet). (b) **DEV**: with the DEV mod on and no subject jumped to, Orbit plays the
   attached cutscene orbit (`sqpm_orbit.lua`, 120 m out, 50 m up, 24 s, Auto Set Speed, locked) around the static
   anchor nearest the view's centre (`world.flyCandidates` within 200 m: an entity with a fat model instance)
   when the view is closer than 450 m (`cutscene orbit: static anchor E (type) N m from the view's centre`); a
   farther view or no anchor: the manual orbit (logged why). A normal-camera "High orbit" (centre 1.5 km+ out) was
   not built: the orbit's centre doesn't move, so it would only change the framing.
5. **"Fast camera bug still happens."** No log (above), so the round 15 `hand-back` / `camera set with no move
   active` lines can't be read; the cause stays the inferred one (findings map-camera.md "The keyboard pan scales
   with the camera's distance"): tours and Wander hand back far / flat views (0658: d 504, eye ~220 m up; Wander
   d 466-654; High ~1700 m) that pan at ~1.2 x d per second. Built, as the user calls it a bug: **the settle**.
   When a tour, Wander or Orbit ends (any path but `stopAll`: pause menu, new game, the window closing; not after
   our cutscenes, whose end gives the player's own view back; not when the player's zoom or tilt ended it), a view
   farther than 1200 m, or farther than 300 m with an eye elevation under 0.6 rad (the camera model; the game's
   usual view ~0.8), eases over 1.5 s (smootherstep) to d = min(d, 550) and pitch = max(p, 0.6) around the same
   look-at point. The player's pan and turn go on during it (x, y, angle read each frame); their zoom or tilt
   ends it; any move, jump, shot, saved view, follow or the cockpit replaces it; it runs with the window closed
   (`D.busy`). Log: `settle (why): d a -> b m, pitch p0 -> p1 (eye elevation e rad) over 1.5 s: the keys will pan
   ~X m/s instead of ~Y`, then `hand-back (settled): ...` or `settle ended by the player's zoom / tilt`. Changes
   the picture after a tour by design; shots never settle (a horizon shot keeps its view). Tests: test_driver
   "round 16: the settle ..." (2).

Open: **the log loss** is a tooling gap (the session-start archive ran mid-session; nothing archives the rest
before the next start). CE runs: archive once more before quitting the game (`uv run tools/game_logs.py save`).

## Round 15 (built in code 2026-10-14, untested: TESTING.md CD1-CD6)

From session `2026-10-14_0658_session` (Hide labels on, High graphics, looks and light, an Aerials tour with Look
Down ended by a pan, Wander, a run of shot presets, the footer's free camera) and the user's report: "I can still
select items in tours (Aerials), still see the jitters, same with other camera moves, can still interact with the
world and hover"; "High should be default, but I like the other options"; "Is there no way to move the camera
programmatically while in free camera mode?"; "Bug with fast movement still there I think?". Files:
`pm_cam.lua` (`AERIAL_LOOK_DEFAULT`), `gui/pm_driver.lua`, `gui/pm_hud.lua`, `gui/pm_world.lua` (`flyCandidates`),
`gui/pm_cutscene.lua`, `description.html`; the DEV mod's `content/mission/keyframes[/en]/sqpm_fly_<h>.lua` and
notes; tests (test_hud, test_driver, test_cutscene, test_world). No new player-facing strings. Nothing here calls
setAppConfig.

1. **High is the default Aerials look** (`cam.AERIAL_LOOK_DEFAULT = "high"`, the driver's `aerialLook`); Down and
   Horizon stay in the Look row. test_driver "round 15: High is the default Aerials look ..." (the older flight
   tests pick Down in `before_each`).
2. **Selection and hover during tours.** Evidence: 07:07:49 `tool actions off (automated camera move)`, 07:07:54
   `Selected entity 26133 (stack = nil, dontBlink = false)`, `Open EntityDetailsTool for 26133 doCloseAll=true`,
   then `view tool: removed by another tool` and round 14's `tool actions back (another tool)`. `stack = nil` is the
   default selector's own onSelect (`selector_react_util.tl:108`; every other selectEntity source passes a
   boolean). In 0633 the empty action alone had no `Selected entity` in three tours. **Cause (inferred, strong)**:
   `setActionsDisabled(true)` leaves the renderer with no active owner, which acts like round 10's tool with no
   action (0055: clicks selected): the renderer falls back to a bound action, and the shelved default tool's
   selector is still bound (`ToolStackEntryWrap` binds every entry; `EntityDetailsTool.shelve` keeps its action). The
   base cutscene task gets away with it because a playing cutscene is a native camera action that takes the input
   (`CameraAction.cpp` strings: `IA_MENU`, `IA_BACK`, `OnSkipCutscene`; findings gui.md). And round 14 then handed
   the actions back when the selection's window cleared the stack. In the 0606 / 0633 orbit cutscenes no `Selected
   entity` was logged (weak: nobody clicked on purpose). **Built: the world lock** (pm_hud `lockWorld`, during every
   automated move and every cutscene of ours; `disableToolActions` never fired for moves):
   - the base selector entity filter (`setSelectorEntityFilter`, game.tl:160, as the campaign's mission_sim fires
     it) set to `{ [-424242] = true }`: the default selector, wherever it is bound, refuses every entity: no hover
     highlight, no selection (inferred: the filter is what keeps streets from highlighting in the normal game).
     `{}` back at the end. Not in a campaign mission (its filter can't be read back);
   - the base disabled features (`setDisableFeatures`, game.tl:166) = the game's table (read with
     `game_react_globals.getDisableFeatures`) + `OpenEntityWindow`: a click that still selects opens no window, so
     it can't clear the stack; the game's table back at the end. One frame later `world lock check: entity windows
     off (the event reached the game)` or `STILL ON`;
   - our empty action stays on top (the 0633 result: no clicks); a tool that clears it during a move gets ours pushed
     back on top at once (stacked: the other tool returns when ours pops), at most `LOCK_REPUSH` = 10 times a move
     (`view tool: removed by another tool during a move, pushed again (n of 10)`). With only "Hide labels" on (the
     normal game) another tool still keeps the map (not pushed back until a new request).
   - Every exit unlocks: the move ending by any path, the pause menu, a new game, a per-frame safety check. The
     action's right-click back works again during moves (round 14 had lost it with the actions off).
   (c) (a mouse-transparent full-screen overlay) not tried: a known crash (findings map-camera.md). Tests: test_hud
   "round 15: ..." (7), "round 10 / 12 / 15: another tool clearing the stack ...". Unverified: whether the filter
   also takes the hover OUTLINE away (if the outline is the renderer's own, only a cutscene removes it): CD1-CD2.
3. **Free camera control from a script: none** (findings map-camera.md "No camera a mod can steer besides the
   normal one and a cutscene"). The binary registers exactly the tealdef's `api.gui.camera` functions
   (`setManualCamera`, `getCameraData`, `setCameraData`, `getHeightAboveTerrain`, `getFollowEntity`, `followEntity`,
   `focusEntity`, `focusPosition`, `isFreeCameraMouseAttached`, `toggleFreeCameraMouseAttachment`,
   `enterFollowCameraCockpit`, `leaveFollowCameraCockpit`, `toggleFreeCamera`, `takeScreenshot`, `world2Screen`,
   `screen2World`, `getEye`, `getCenter`, `getNearFar`, `traceToTerrain`); the free camera is `FollowAction` without
   an entity, steered only by the player; `setCameraData` sets the normal camera (three sessions); the Advanced
   Camera Tool has no Lua functions. Verified: the function list (strings); inferred: that nothing else reaches the
   free camera (C++).
4. **The DEV cutscene aerial** (pm_cutscene `FLY`, `planFly`; pm_driver `cutsceneFly` / `flyStep`; pm_world
   `flyCandidates`; DEV keyframe files `sqpm_fly_<h>.lua`). The entity map as the data channel: a static file whose
   key i is attached to its own placeholder `9999900 + i - 1`, `FLY.height` = 250 m straight above it (an offset
   the same in any entity frame), looking along the file's heading 20 degrees down (`pitch -0.35`), every key's
   speed `leg / legS` = 600 m / 15 s = 40 m/s, 6 keys = 75 s. The GUI picks the anchors: from the view's centre
   along the look (eye -> centre heading, rounded to 8 headings; the next nearest headings when a line leaves the
   map or finds no anchor), anchor i = the candidate nearest to one leg on from anchor i - 1 (no drift; legs within
   +- 2 x `searchR` = 150 m), candidates from the octree (`MODEL_INSTANCE_LIST`, `ASSET_GROUP`, `CONSTRUCTION`)
   with a FAT model instance (the transform an attachment needs, positioned by it; carriages, people, animals and
   moving things skipped); per-type counts logged. Chain: up to 4 flights (5 min), the next planned from the last
   anchor; played 0.5 s before the running one ends (`a second playCutscene REPLACES / does NOT replace the running
   one`), else after its end (`hand-over: N frame(s) not playing, the eye jumped D m`). Logged per flight: the
   anchors and legs, `attached` / `NOT attached` 0.4 s in (eye within 60 m of anchor 1 + 250 m), `cutscene fly key
   i`: the eye against the anchor it should be above and the look heading against the file's; at the end `eye
   smoothness (cutscene fly)` and the game speed back. Esc (the game's skip) ends it early (`ended early ...`); the
   pause menu / window plays no further flight. Hover off + the world lock during it (a cutscene counts as an
   automated move). With the DEV mod on, Start in Aerials plays it; no anchors: the normal tour. Inferred /
   open: whether keys on different entities interpolate (the campaign only cuts between them, findings
   environment.md), which entity types resolve, the pace with uneven legs. Tests: test_cutscene "round 15: ..."
   (4), test_driver "round 15 DEV: ..." (4), test_world "round 15: flyCandidates ...". CD4.
5. **"Fast movement" after tours / shots.** In 0658 no camera write of Photo Mode's after a move ended (D.step
   returns idle; `camera_step` counts frames only), no setting changed (the window's HQ is graphics only). The data
   that fits: the keyboard pan moves ~1.2 x the camera's distance per second (0434 measured), and the views Photo
   Mode hands back are far from their look-at point with a flat look: the 0658 tour ended at `read=-635,1146,504,
   -2.057,0.070` (d 504, eye ~220 m up), the Wander at d 466-654 (eye 100-200 m up), `highhorizon` at d 4000 (eye
   ~800 m up): 2-5 x the pan speed of the game's own camera at that height (its model steepens far views).
   **Inferred**, not a bug in our code. Built: a `hand-back (why): d=, the eye h m over the look-at point,
   d/height=, pitch=; the keys pan ~v m/s` line at every move end and every shot, and `camera set with no move
   active (src ...)` whenever a per-frame path (or an unnamed caller) sets the camera with no move or follow release
   running (at most 8 lines; none expected). Not built: easing the view to a nearer distance at the end (it changes
   the picture); CD5 decides whether it is the cause (a zoom in makes it go away) and whether to ease it.

## Round 14 (built in code 2026-10-14, untested: TESTING.md CC1-CC5)

From session `2026-10-14_0633_session` (Hide labels on, two Aerials tours with Look High, one with Look Down of
four legs, a jump to a road vehicle and the DEV orbit cutscene; 10 `eye spike` reports, 80 `cam trace`, 14
`cutscene orbit t=` lines) and the user's results; one more load hang with the big mod set
(`2026-10-14_0632_sqsg-crash`: test with Photo Mode + DEV only). Files: `gui/pm_hud.lua`, `gui/pm_driver.lua`,
`gui/pm_world.lua`, `pm_cam.lua`, `pm_flight.lua` (`EYE.blendS`), `content/mission/keyframes[/en]/sqpm_orbit.lua`,
`gui/pm_window.lua` + `strings.json` (the shots' note, 12 languages), `description.html`; tests (test_hud,
test_driver, test_cutscene, test_flight). Nothing here calls setAppConfig.

1. **Hover still active during tours** (user, Look High: "smooth" but "hover still active"). Log: `view tool on
   (labels hidden): ... action set`, every tour `hover off (automated camera move)`, `tour: ... view tool on`, and
   no `Selected entity` in the whole session: the empty action (round 11) stopped click-to-select, so the top
   entry's action WAS ours, yet the outline stayed. So the outline is not a Selector child of the active action
   (there is none); the renderer draws it while it has any action owner (inferred; C++). The base game's own way to
   take the map's mouse away is the cutscene task's: `api.gui.fireReactEvent("disableToolActions", true)` before
   `playCutscene`, false at its end (`mission/tasks/cutscene/cutscene.tl:39`, `:51`) -> `game.tl:401` ->
   `ToolStack.setActionsDisabled` -> `RendererComponent.setActiveOwnerOverride(nil)` (`builtin.lua` ~1393, ~527):
   NO action owner at all. **Built** (pm_hud "tool", `setActionsOff`): fired true when an automated move starts
   (tours, Wander, Orbit; with the existing hover-off), false when it ends by any path, at the pause menu, when
   another tool takes over (a build menu: it needs its action), at a game start, and by a per-frame safety check
   (actions off with no move running). Not for "Hide labels and hover" alone: the switch is global, a build menu
   opened meanwhile would get no action either (CC1e asks whether the outline shows there). Cost: the action's
   right-click back (round 11) can't fire during a move; camera input, Esc and the pause key still end it
   (description updated). Unverified: whether the labels show with no action ("Hide labels during tours"
   unticked: CC1c). Tests: test_hud "round 14: ..." (one pair per move, every exit, the safety check, another tool,
   a failing fireReactEvent, labels alone untouched).
2. **Look Down jolts** (user: "slight jerk after the camera was panning up then goes down, big jerks before a big
   hill, jerk going over a factory, maybe jerk is when camera tilts up or down; really glitchy tilt going over a
   river and a mountain before the airport"). Down legs: `spikes=` 7 / 44 / 32 / 42, d2 max 27 / 58 / 33 / 2 m,
   speed max up to 3823 m/s, look d2 max 0.063 rad. **The 10 reports, classified** (test_flight "round 14: the
   0633 spike reports, classified"; findings map-camera.md "Tour eye jolts from the game's centre"):
   | # | look | kind | evidence |
   |---|---|---|---|
   | 1 | High | long frame | raw 32.2 m, at the frames' own times 2.24 m (dt 0.045 among 0.019) |
   | 2 | High | input | `read-sent=3.4,0,0`: the player's pan (the tour ended "camera moved: pan" 1 frame later) |
   | 3 | Down | centre | centre 99.9 vs model 93.9 (+6.0), eye +6.2; g under the centre 101.8 -> 89.9 in 4 frames (-7.3 in the last); blend on |
   | 4 | Down | centre (river) | g -12.5 (under water), the model's max(g, 0) + 4 = 4.0, the game 12.4 (+8.4), eye +8.3; also a long frame (raw 13.4) |
   | 5 | Down | model residual | centre = model; eye 1.3 m off at d ~1.6 km (the model's elevation residual there) |
   | 6 | Down | centre | +3.4 (eye +3.3); g 29.4 -> 19.5 (-6.2 in the last frame); blend on |
   | 7 | Down | centre | +1.6 (eye +0.9, d 846); g 207 -> 194 (-13 in one frame); blend on |
   | 8 | Down | centre | +1.6 (eye +1.6); g falling steadily 143.9 -> 141.1; blend on |
   | 9 | Down | centre | +2.6 (eye +2.7); g 134.4 -> 132.6; blend on |
   | 10 | Down | centre | +4.0 (eye +3.9); g 141.7 -> 136.0 (-4.7 in one frame) |
   Every Down jolt but the residual is the game's centre ABOVE `getHeightAt + 4` (never below), where the ground
   under the look-at point falls steeply (a terrace or cut edge: industries, roads, embankments, "a factory", "a
   mountain before the airport") or is a river ("glitchy tilt over a river"); the engine eye rises by the same.
   **The user's tilt hypothesis holds**: in 5 of those 6 the solver's meeting point had just jumped (`blend=true`:
   the look's ray met a steep face) and the leg's look d2 max (0.063 rad at f=1851) sat 3 frames after report 3;
   the look tilts where the eye jolts, both at steep ground under the look-at point. The 58 m d2 at f=58 of leg 2
   (river waypoint, 10 frames after report 4, no report left in the gap) is unexplained (no trace there).
   **What the data supports**:
   - The Down look can't be made smooth with the game's centre where it is: below 800 m out its z couples 1:1 to
     whatever surface the game uses there, and that surface is not `getHeightAt` at cuts / terraces / rivers. The
     800-1500 m band (the "Mid" idea, coupling S(d)) only helps far up: at d 1350 the game's flattest look puts the
     eye ~690 m above the centre (S = 0.12), at d 1000 ~470 m but S = 0.85; such a look is nearly High. **Not
     built**; **recommendation: make High the default Look** (the user's call; smooth in both 0633 High tours:
     `spikes=0`, d2 max 0.35-0.51 m).
   - **Which surface?** Two candidates, both cheap to test in game: the terrain's BASE height (`getBaseHeightAt`:
     without the alignments roads, tracks and industries cut; the 0606 jolt "merged into the slope above", a cut's
     shape) and a river's water level (water meshes carry a `waterLevel` per tile; report 4: the game 8.4 m above
     the sea rule over a river bed at -12.5). **Built** (pm_driver "centre fit", pm_world `baseGroundAt` /
     `waterAt`): every frame of a move compares the game's centre (read, for last frame's view) with the model;
     where it is more than 1 m off it reads the base height and water there; one `centre fit (tour): frames= off>1m=
     base height fits= on water= worst ...` line per move, and `base= water=` in every spike report. If the base
     height fits, the solver's ground becomes `max(getHeightAt, getBaseHeightAt)` (or the base) next round, which
     would remove these jolts for Down too. CC4.
   - **Gentler tilt**: the meeting-point blend (round 9, `EYE.blendS`) 0.5 -> 1.0 s: on test_flight's bumpy ground
     the look's largest step a frame 0.0110 -> 0.0062 rad (frames off the plan 59 -> 126 of 3601). The eye is
     unchanged (exact either way).
3. **The DEV orbit's pulse** (user: attached and follows, eye-subject 126.9-134.1 m, d2 max 1.04 m, "a strange
   glitchy movement like a pulse"). **Cause (inferred, strong)**: the keys' `speed`. The binary's CameraAction
   moves the camera along a spline by distance (`m_data->splineDist`), and the Advanced Camera Tool's key list has
   "Time", "Speed" and "Auto Set Speed"; the campaign's keys hold exactly the chord to the next key over its time
   (MISSION_01_CUTSCENE_OUTRO_A: 14.034655 m / 15 s = 0.935644, the file's speed; a cut's end key repeats its
   segment's; interior keys the mean of both segments: MISSION_07_CUTSCENE_BONUS_COMPLETE 38.787 = (39.531 +
   38.042) / 2). Round 13's keys all said 1 m/s on 31.4 m segments: a crawl at each key, a rush between, once a
   second. The session's eye acceleration rms (d2 rms 0.055 m at ~16 ms frames: ~200 m/s2) is 25x an even
   circle's 8 m/s2 and matches a cubic segment with end speeds 1 (peak 6L/T^2 = 188 m/s2). Also **the offsets
   turned with the vehicle** (lockYaw false): the bearing gained what the vehicle's heading turned (bearing -
   heading +0.50..+0.53 rad per 2 s, the orbit's 0.52; the bearing alone +1.11, +1.01, +0.45 ... +0.01): the
   orbit's pace changed at every bend. **Built**: the orbit file sets every key's speed by the game's Auto Set
   Speed (`autoSpeed`: 31.37 m/s for all 25 keys) and locks yaw / pitch / roll (inferred meaning: the camera
   tool's "Lock Yaw / Pitch / Roll"; CC3 checks); the driver logs `cutscene orbit pace around the subject a-b m/s
   mean M spread S %` (the eye's motion relative to the subject from 1 s in) and `heading=` / `rel=` in the t=
   lines. Tests: test_cutscene "round 14: the orbit's key speeds ..." (even, locked; the round 13 keys' cubic
   1-47 m/s), "Auto Set Speed matches the campaign's keys", test_driver "round 14 DEV: the orbit's pace ...".
4. **Shots come back to the same place** (user: "I go to Eye level, then High horizon, then Eye level, and it's not
   where I started"). Cause: every preset took the CURRENT centre, and the horizon shots push their centre d cos p
   ahead (`cam.horizonShot`): the next shot started 3-4 km further on. No Ken Burns drift after a shot (only tours
   drift). **Built**: `cam.shotAnchor` / `D.shot`: the first shot takes the anchor (the current centre and angle);
   every further shot is framed from it while the camera still shows the view the last shot sent (centre within 2 m
   + 0.5 % of the distance, the same angle; a zoom or tilt of the player's keeps it); a pan / turn takes a new one
   ("camera moved" / "camera turned"), and a jump, a follow, the cockpit or an automated move resets it. Log `shot
   anchor kept|new (reason) x,y a=`. The shots' note (Camera tab) says so (12 languages). Tests: test_driver
   "round 14: Eye level -> High horizon -> Eye level ..." (identical within 0.01 over a run of every preset), "a
   zoom or tilt keeps the anchor; a pan or a turn takes a new one", "a jump or an automated move takes a new
   anchor", "the anchor survives a NaN read".
5. **Free camera verified** (user, 0633: "free camera button works that time, actually uses free camera"): round
   13's removal of `toggleFreeCameraMouseAttachment` made the footer's Free camera the game bar's (findings gui.md;
   TESTING.md CB6b passed).

## Round 13 (built in code 2026-10-14, untested: TESTING.md CB1-CB8)

From session `2026-10-14_0434_session` (free camera once, the smooth camera with 13 click glides, High graphics,
Hide labels, looks, the Light tab, 2x screenshots, a "This place" tour at 04:43:34 and an Aerials tour at 04:47:14;
600 `smooth trace`, 60 `eye spike` (12 reports), 60 `cam trace` lines; the DEV mod off, so no cutscene ran) and
three requests. Files: `pm_driver.lua`, `pm_hud.lua`, `pm_window.lua`, `pm_flight.lua`, `pm_button.script.lua`,
`gui/pm_cutscene.lua`, new `content/mission/keyframes[/en]/sqpm_orbit.lua`, `strings.json` (12 keys x 12 languages
removed), `description.html`, `docs/ui-guide.md`, the DEV mod's notes; tests. Nothing here calls setAppConfig.

1. **The smooth camera is removed** (user: "Smooth (camera) still jerky, we might have to give up on it"; its click
   glides logged `d2 max` up to 38 m, `speed max` 1821 m/s). Why it can't work: the game draws each key step before
   any mod code runs (findings map-camera.md "Smooth camera: the game draws a key's step"), the only lever (a lower
   keyboard camera speed) can't be kept out of the settings file (round 12 item 1), and the glides' worst frames
   were the player's own input (item 3a). Gone: the footer's Smooth camera button, the Camera tab's Smooth camera
   section (Smoothing, Level zoom), the driver's smooth camera / click glide / `smooth trace` lines
   (`toggleSmoothCam`, `smoothClick`, `setSmoothStrength`, `setLevelZoom`, `stopSmoothCam`, `D.onSmoothCam`),
   pm_flight's `SMOOTHCAM` / `cdStep` / `newSmoothCam` / `smoothCamStep` / `smoothCamLevel` / `CLICK_GLIDE`, pm_hud's
   `setSmoothCam` and the click selector (`H.onWorldClick`), their tests, strings and description text. Kept (tours
   use them): the view tool and its action, the eye-space solver, the smoothness metric and spike reports, the
   right-click back (now only during a move, item 2), the pause-key escape hatch. The footer: Free camera alone on
   the left (FOOT_LEFT_W unchanged), the screenshot group right.
2. **"Moving around becomes hyper sensitive" after some interaction** (back in the normal game). Every path that
   touches camera or input state, checked:
   - `setAppConfig`: only High graphics' six graphics keys (pm_core `KEYS`), never a camera, mouse or keyboard key;
     the player's `settings.lua` after the session holds their own values (`mouseMovementSensitivity` 5,
     `keyboardCameraSpeed.game` 0.5, `resolutionScale` 0.7, `cameraTool` false). The keyboard pan speed in the
     session's `smooth trace` stayed 1.1-1.3 x the distance per second from the first to the last input frame
     (also in `2026-10-14_0055_session`'s two smooth camera runs): no change measured in what the keys do.
   - The free camera's mouse attachment: Photo Mode toggled it (`toggleFreeCameraMouseAttachment`, "mouse detached
     from the free camera" at 04:36:39) at every push since round 6, for tours that no longer use the free camera.
     No base code ever calls it; it is native input state of unknown reach (the warning `Cannot leave cockpit as
     action does not match` at the exit is the game's own, also without Photo Mode: findings gui.md). **Removed**:
     the footer's Free camera is now exactly the game bar's (test_hud "the footer's Camera mode", "round 13: after
     free camera...").
   - Our view tool: kept on the stack in the normal game while "Hide labels and hover" is on, and its action carried
     the right-click back (`onBack`) all the time: with only the labels hidden a right click (the game's "Back With
     Right-Click") went to Photo Mode ("back (right click): nothing to end") instead of closing a window or
     aborting. Now the back is set only while a move runs (re-set when one starts or ends; test_hud "round 13: the
     right-click back only while a move runs").
   - The smooth camera (an eased camera for minutes; the normal one feels abrupt after it): removed (item 1).
   - High graphics stays on after the window closes (by design): the frame rate drops (MSAA 8, 100 % scale), the
     camera's speed per second doesn't (time-based). Not changed; CB1 tells whether it is the cause.
   - Game speed: the Light tab's freeze and the tour's pause restore the speed they found (logged `speed 1 back`);
     the cutscene restores it too. Unchanged.
   - Restores on every exit (pause menu, new game, window close, the pause key): the tool popped, the UI root and
     window shown, the selector allowed, the free camera popped (test_hud "round 13: after free camera, hidden labels
     and a tour, the pause menu leaves nothing of ours").
   Cause **not proven**: no log line shows it (Photo Mode logs nothing in the normal camera). The two changes remove
   the only input state Photo Mode changed. CB1 narrows it down if it comes back.
3. **Tours and the free camera** (user: "One of the main issues is still the tours not using free camera mode";
   wanted: no UI, no hover / outline, no pointer, motion not tied to the terrain).
   (a) **The 12 eye spike reports, quantitatively** (findings map-camera.md "Single-frame eye spikes", update): all
   in the smooth camera's glides (the budget was spent before the tours). In every report the engine eye was 0.7 m
   from the model's eye for the view read (constant), the game's centre z equalled the model's to 0.1 m, nothing
   clamped / guarded / blended / lifted. 7 of 12 followed a long frame (20-31 ms among 15 ms): the eye moved exactly
   on its timed path; the per-frame second difference spiked only because it ignored the frame time (spike 4's
   frames: raw 2.95 / 3.56 m, at the frames' own times 0.48 / 0.29 m). 5 of 12 (one glide) read a distance 3.8-10.4
   m off the one sent (inferred: the player's wheel during the glide, which ended by input 30 frames later). The
   moves' big `d2 max` values sat in the frames the player's input ended them (tour f=1731 of 1733, glides f=115 /
   f=58). And the eye read in onStep shows the view sent the frame BEFORE (each spike's model eye = the previous
   frame's plan), so the metric paired each step with the wrong frame time. **No game mechanism found; the metric
   fixed**: d2 = |v(i) - v(i-1)| x the mean frame time (equal to the plain second difference for even frames;
   `raw=` keeps the plain one in the spike line), the step paired with the previous frame's dt (`S.prevDt`), the
   player's look input during a flight cuts the chain (no longer counted as the camera's jolt), at most 4 spike
   reports a move and 16 a session (a later tour still gets its own), a look jolt over 0.05 rad reports too (the
   "This place" hops had `look d2 max` 0.060 / 0.079 rad, unexplained), and the spike line adds `read-sent=` (the
   read view minus the one sent). Tests: test_flight "round 13: replay of the 0434 session's eye spikes 4-5"
   (the logged plans and dts), test_driver "round 13: uneven frame times are no eye spike", "eye spike reports: at
   most a few per move". What stays open: the 0229 session's tour spikes (f=394 / f=84, mid-move), which this
   session didn't reproduce; CB3 brings reports from tours.
   (b) **Hover / pointer during the two tours**: `tour: window hidden, game UI hidden, view tool on` both times
   (04:43:34, 04:47:14), no `Selected entity` during either (the only one at 04:36:37, before any tour). Whether the
   cursor hid (our action's `mouseCursor` = the base "None", 1009) and whether an outline showed is not in the log:
   the player didn't report hover this time. `mouseCursor` is not a field of the typed `ActionDescriptorParam`
   (`builtin.d.tl:1338`), but the construction tools pass it the same way (`construction_react_util.tl:1420`); CB3
   asks.
   (c) **Routes to a camera that isn't bound to the terrain**, from the game files and the binary (findings
   map-camera.md "The Advanced Camera Tool", environment.md "Cutscenes from a mod"), ranked:
   1. **The game's Advanced Camera Tool** (Settings > Advanced > "Enable Advanced Camera Tool"): a native window
      (`cameraManagerWindow`, C++ `UI::CameraManager`) for keyframed camera paths: Insert adds the current camera as
      a key, Space plays, Return records frames, save / load (userdata `keyframes/`, `recordings/`), focal length,
      resolution, game speed. Its keys are the cutscene structure. It is the game's own smooth, terrain-free
      playback; the window even stays (transparent) while the UI is hidden. A mod can open it (`setVisible`), not
      add keys or press play. **Decisive and cheap: the player tries it by hand (CB4)**: if its playback is what a
      tour should look like (no UI, no outline, no pointer, smooth), Photo Mode's job becomes feeding it (key files
      written to `keyframes/`, which needs `io` in the GUI state: CA6 / CB5) or helping the player set keys.
   2. **A cutscene attached to an entity (built, DEV, CB2)**: the campaign attaches keys to entity ids and maps them
      to live entities at play (`playCutscene`'s third argument; mission_01 maps two moving trains' carriages). So
      a FIXED keyframe file needs no file channel: `sqpm_orbit.lua` computes one turn around a placeholder entity
      (`C.ANCHOR`; r 120 m, 50 m up, 24 s, a key a second, looking at it) in its own `data()` with plain math;
      `pm_cutscene.playOrbit(anchor)` maps the anchor to the subject (a vehicle's carriage, as the campaign; item 4
      fixed the mapping) and plays it (tool actions off as the base task). With the DEV mod on, the Camera tab's
      **Orbit right after a jump** plays it around that subject; `cutscene orbit t= eye= subject= dist= bearing= dz=`
      lines and `cutscene orbit end ... eye-subject distance a-b m (an attached orbit: 130.0)` tell whether the
      attachment works (distance ~130 m), whether it rides along with a moving vehicle, and whether the offsets turn
      with it (the bearing). If it works, tours could be chains of such templates around subjects (orbits, fly-bys,
      chase shots) with no terrain anywhere in the path; open: how a chain hands over between plays (the camera
      returns to the normal view after each), player input ending one early, and static anchors (a construction).
   3. ~~A cutscene fed by a keys file (round 12, DEV, CA6)~~: closed (item 4): the GUI state has no `io`.
   4. **The normal camera with the eye-space solver** (today's tours): smooth to the metric now that it is honest
      (eye checks within 0.1 m in this session); the cursor / hover handled by our tool. Stays the default.
   5. Rejected: the free camera (no setter; three sessions); followEntity / the cockpit (entity-bound; a GUI script
      can't create or move an entity: building one is a real construction through a proposal, not a transient
      marker); setManualCamera / focusPosition (the normal camera again).
   What the user must test next: CB4 (the camera tool by hand: the cheapest, decides route 1), CB2 (the attached
   orbit, DEV), CB3 (a tour's spike reports and the cursor).
4. **CB2's first run and the fix (session `2026-10-14_0606_session`, built in code 2026-10-14, untested: CB2)**. A
   jump to road vehicle 95565, then Orbit with the DEV mod: the file's `data()` gave 25 keys (math), the orbit
   played its 24 s, but the engine logged `Invalid entity for attachment` (`CameraAction.cpp(180): GetTransform`)
   34,075 times (every frame) and the eye flew the keys' raw offsets around the MAP ORIGIN (eye 120, 0, 50 ->
   -120, ...; eye-subject 750-1003 m instead of 130). Good news in the same run: the playback was very smooth
   (`eye smoothness (cutscene)` 1361 frames, d2 max 0.72 m, rms 0.05 m, speed max 52 m/s) and not terrain-bound.
   - **The mapping** (findings environment.md "Cutscenes from a mod"): `playCutscene(file, true, { [idInFile] =
     liveEntity })`, plain integer keys (`api/tealdef/api/gui.d.tl:753-754`; mission_01 `mission_story.tl:86-97`
     `{ [33846] = carriages[1], [20790] = carriages[2] }`; mission_08 `mission_story.tl:890-897` `{ [167181] =
     rocketEntity.entity }`); our map had that form. The live entity in every campaign case carries a transform of
     its own: a carriage (`CARRIAGE_LIST.carriages[1]` of the Mardi Gras floats, which are ROAD vehicles: bought
     in `entity_newOrleansRoadDepot`, mission_01 `:2625`) or a spawned custom model (`custom_entity_util.spawn`,
     transform in `MODEL_INSTANCE_LIST.fatInstances[1]`). **What was wrong**: `anchorFor` read the vehicle's
     `CARRIAGE_LIST` but accepted it only when `type(cl) == "table"`; the game hands components as userdata
     (inferred: the fallback "else the entity" ran for a road vehicle that has a carriage list, as the floats do),
     so it mapped the transport vehicle 95565 itself, which has no transform of its own.
   - **Fix**: `anchorFor(entity, comp, conOf)` reads components without type checks (fields in pcall) and picks a
     vehicle's middle carriage (any carriage is valid; the middle frames a train), a carriage itself, or an entity
     with a `MODEL_INSTANCE_LIST` fat instance (for a station group also its first station and that station's
     construction: untested); otherwise nil and why, and Orbit plays the normal orbit (`not attachable (...)`).
     The placeholder id is now 9999999 (an integer key like the campaign's, never a list index, far above save ids,
     exact as a float32) instead of 1. The play line logs the anchor, how it was chosen and the map.
   - **Error spam**: no api validates an attachment or stops a cutscene (`api.gui.mission` has only
     `playCutscene`, `isCutscenePlaying`, `getCutsceneElapsedTime`; the player's Skip is the native
     `IA_SKIP_VOICEOVER_AND_CUTSCENE`). So 0.4 s in, the eye-subject distance decides (`attachVerdict`: within
     1.5 x 130 + 20 m attached, beyond 3 x 130 + 100 m not): logged once (`cutscene orbit attached: ...` / `NOT
     attached: ... ending it`), and a detached orbit gets `sqpm_stop.lua` (a 0.1 s still frame) played over it.
     Whether a second `playCutscene` replaces a running one is open (CB2 logs it: the end time).
   - **Game speed**: the restore was right (the player's 4 read before the play, the cutscene left 1, we sent 4);
     the end line said `game speed 4 -> 1`, which read backwards. Now `game speed back to the player's 4 (the
     cutscene left 1)` or `game speed N kept`.
   - **The keys-file channel is closed**: the same run logged `GUI state io=nil os=table load=function dofile=nil
     debug=table require=function`. The GUI can't write a file; `load` only compiles strings in its own state,
     and the keyframe file's state is a fresh one per play with no shared globals (round 12 T9: a global set in
     the GUI was not visible there). Removed: `C.flightKeys` / `serialize` / `writeKeys` / `play` / `chunkPath` /
     `keysPath` / `envText`, the driver's `cutsceneFlight` (Aerials with the DEV mod is a normal tour again),
     `sqpm_flight.lua` (both copies) and their tests. CA6 and CB5 are closed.
5. **Aerials by default; the tour's eye jolts (session `2026-10-14_0606_session`, built in code 2026-10-14,
   untested: CB7, CB8)**. User: "Aerials should be the default mode. I'm in Aerials now, still jumps as we move up
   terrain and sometimes when the camera shifts."
   - **Default**: `cam.TOUR_MODE_DEFAULT = "aerial"` (the driver's `tourMode` and its preset ranges); the Look stays
     Down. test_driver "round 13: Aerials is the default tour mode" (the older driver tests pick Ground level in
     `before_each`).
   - **The jolts, quantitatively** (findings map-camera.md "Tour eye jolts from the game's centre"): the tour's 4
     spike reports (frames 66-70, d 127-132 m, in the glide up from the vehicle) are ONE event: the game's centre
     2.2-3.0 m above getHeightAt + 4 for three frames (#65-#67) on a slope, the engine eye lifted as much; the
     game kept its camera model otherwise. (a) The centre's z is getHeightAt + 4 everywhere else (558 trace frames,
     32 eye checks, 14 other reports): not smoothed, not lagged (non-monotonic along a monotonic slope), not a
     footprint max (zero offset further up the same slope); inferred: something on the ground the height query
     doesn't show (an embankment or deck, a vehicle, another interpolation). (b) The sent views' uneven steps
     (distance +2.8 / +1.1 / +3.7 / +1.3 m) are the look meeting a steepening slope; the model puts each on its
     planned eye within 0.13 m: not the cause. Spikes 3-4 were the eye coming back down when the offset ended.
     Replay (test_flight "round 13b: replay of the 0606 session"): the logged views + offsets give 2.86 / 3.08 /
     1.51 / 2.25 m against the reported 2.87 / 3.04 / 1.62 / 2.27.
   - **Options weighed**: a smoothed ground surface for the solver (the game's centre uses the real one: it would
     add a bob everywhere and still step at the unseen 3 m); the centre read as feedback (one frame late: the
     replay's jolt doubles, 6.26 m); a damped follower on the distance (moves the eye off the model, no help for
     a step it can't see); a higher Drone altitude (below 800 m out the centre's z couples 1:1, so a 3 m step stays
     3 m, only a little less visible). **Only a look-at point 1.5 km+ out is immune** (the game's centre at the
     water level whatever the ground). Built as an option, not a new default (it changes the picture: ~1 km up):
     the Aerials **Look "High"** (`cam.AERIAL_LOOKS` third entry, `pm_flight.HIGH` / `highPose`: d 1700 +- 80 m,
     never under 1600, elevation 0.64 rad, the eye 4 + d sin(e) ~ 0.97-1.07 km above the sea, lifted to stay 300 m
     over high ground, the heading towards the path d cos(e) ahead; within the zoom limit). Replay over the logged
     ground with the 3 m offset: Drone d2 3.0 m, High 0.000 m (test_flight "round 13b: the High look ...",
     test_driver "round 13: Aerials look High ..."). 2 strings x 12 languages; description.
   - **Diagnosis of what is left** (the tour's d2 30 m at f=1573 had no report): one spike report per jolt (the
     next only `EYE_SPIKE_GAP` = 30 frames after the last spike frame), up to 8 a move (was 4) and 24 a session
     (was 16); every frame over the threshold counted in the smoothness lines (`spikes=N`).

## Phase 3: Light & weather (built 2026-10-13, untested: TESTING.md L1-L9)

New "Light" tab (`pm_window.lightTab`, `gui/pm_sky.lua`, pure `pm_light.lua`). Calls as the base "Weather &
Time" window makes them (`base/content/gui/game_bar/game_bar_widgets.tl` ~404-560; the game script
`game_mechanics/game_time/game_time.script.tl`):

| What | Read | Set |
|---|---|---|
| time of day | `GAME_TIME.timeOfDaySec` | `api.cmd.makeGameSetTimeOfDayCmd(integer s)` |
| time cycle | `getEntityForGameScript("::/game_mechanics/game_time/game_time.gs")` → `GAME_SCRIPT.state.timeOfDayMode` (Constant = the widget's "Custom", Automatic, Local, Dynamic) | `makeScriptingSendEventCmd("", "GameTime", "SetMode", { mode = m })` |
| clouds | `api.gui.rendering.getEnvironment().atmosphere.cloudCoverage` | the environment copy + `setEnvironment` (as the widget) and `makeGameSetCloudCoverageCmd(c)` (the sim's `WORLD.cloudCoverage`, which the Dynamic weather drives) |
| weather cycle | the same state's `weatherMode` (`or "Constant"`, as the widget) | `makeScriptingSendEventCmd("", "CloudCoverage", "SetMode", { weatherMode = m })` (ids verified in the script's handleEvent) |
| season, sun | the environment's `atmosphere.dayOfYear` (climates use 171), `.sunRotation` (radians, as model_editor env files) | the environment copy |
| freeze | `GAME_SPEED.speedup` | `makeGameSetSpeedCmd(0)` / the kept speed |

- **Override** ("Light & weather override" checkbox at the top; a preset or step button ticks it): snapshot of
  the eight values (time, clouds, day, sun, the two cycles; phase 4 added `cloudBase` / `cloudTop`, tolerance
  5 m), both cycles to Constant (a cycle that can't be read is left alone), marker `light = { orig,
  set }` in our GUI save data. Restore = `pm_light.recoverPlan`: only values still ours go back (time within
  120 s, clouds 0.02, modes still Constant), a value or cycle the player changed meanwhile stays; order time →
  time cycle → environment → weather cycle. Restored on untick, the pause menu and the next load (the marker:
  a save made while overridden stores Constant cycles in the savegame's game-script state; the next load with the
  mod repairs it). Not on window close (as High graphics mode). Removing the mod while overridden leaves the
  cycles on "Custom": the calendar's Weather & Time panel switches them back (description, the tab's note).
- **Presets**: Golden hour (sun 6° up in the evening), Blue hour (sun 4° below the horizon), Noon 12:00, Night
  00:00, Clear 0, Overcast 0.7, Storm 1.0 cloud cover (the base "rainy" weather's mean; there is no rain field
  in `Environment.AthmostphereParams`, so whether 1.0 rains is to be seen: L2). Sun times: textbook declination
  with the day of year shown and the current climate's latitude (phase 4: `pm_weather.latitude()`, from the
  climate's env file; the Environment record exposes none; before: always temperate 0.7068 rad),
  assuming the game clock is solar time (L3); a day the sun never reaches the angle: 18:30 / 20:45.
- **Step buttons** (`docs/ui-guide.md` "Step control"): time ±1 h / ±10 min, clouds ±10 %, season ±15 days, sun
  direction ±15°, ASCII arrows (`<<`, `<`, `>`, `>>`; Lato's coverage of « ‹ is unchecked), the value between
  them (what we set while overridden: the commands land a tick later). No slider: a slider's change callback
  sends a command per pixel and our window re-renders on change (a re-render mid-drag is untested).
- **Freeze time** (checkbox): `makeGameSetSpeedCmd(0)` with the speed kept; untick / pause menu / next load:
  the kept speed back if the game is still paused. While frozen `pm_sky.stepFrame` reads the speed once a frame:
  the player unpausing (game bar, Space) ends the freeze, nothing to restore.
- Logs: `light override on: player's ...`, `light preset <key>: ...`, `light step <field>: ...`, `light override
  off (<why>): restored ... | kept ...`, `light freeze on|off ...`, `light freeze ended by the player`, `light: a save
  made while overridden; restored ...`, `light ... ERROR ...`.

## Round 11 looks (built 2026-10-14, untested: TESTING.md K14-K19)

User (after `2026-10-14_0055_session`, every look switched fine): "Can the looks be mixed and matched? e.g. hazy
morning and mirror water"; "Some looks aren't different enough. Push them further"; "A way to make a river look
more extreme, rapids etc.?"; "Can the way looks are applied be leveraged for depth of field? Or can we add
shaders?"; then "photo mode is too long, we need more tabs, one for the light, one for weather".

- **Layers** (LOOKS.md "Layers"): a sky look (the env file's `atmosphere` + `light` blocks: Hazy morning, Crisp &
  clear, Misty valley, Dramatic, Storybook, Moonlit night) and a water look (the `water` block: Mirror water,
  Crystal clear, Stormy sea, Wild water), each with "Original". Only six atmosphere fields are live, so every
  pair is its own generated file: 4 climates x (7 x 5 - 1) = **136 files, 578 KB** (was 32). Clouds, day and sun
  stay live (carried over every switch). The generator checks that the two layers change disjoint fields
  (Stormy owns the overcast-only `hdrContrastOvercast` / `hdrExposureOvercast`); test_looks checks every pair is
  its sky file's atmosphere + light and its water file's water. Mirror and Stormy moved from looks to water
  looks; Stormy's dark ambient went (the sky layer owns `ambientDayColor`).
- **Pushed further** (LOOKS.md "Looks" table: every change per look): mie x6-x10 with tinted mie colours, fog up
  to 24, sun disc x1.8 and bloom 80, contrast +0.6 / -0.35, moon x8, ambient tints doubled; inside the wiki's
  ranges (the generator fails otherwise; new bounds for sunSizeAngle, absorptionScale, hdrContrastDay,
  hdrExposureOvercast, normalScale up to 8). The campaign's own env files go as far (mission mie 0.107, fog 23.8).
- **Wild water** (rapids): `normalScale` 6 (the shader scales wave strength by water depth, about 0.16-0.5 in a
  river: a river then gets a stormy sea's chop), high-frequency motion, roughness 0.6, shoreline foam,
  extinction x8. The engine has no flow speed or direction (findings environment.md "Water"), so rivers don't
  run downstream; a custom water normal map (DDS) is the next step if it isn't wild enough.
- **Depth of field / shaders**: none in env files, api or cutscenes; mods may ship shaders on PC only (guidelines:
  none on consoles). Not built: proposals in LOOKS.md "Depth of field".
- **Tabs**: Light (override, time presets, time-lapse, season and sun, time / season / sun steps, freeze) and a new
  Weather tab (override, looks as two ComboBox rows, cloud presets, weather over time, cloud steps). Six text tab
  labels don't fit 440 px in 10 of 13 languages (ko / zh only at the small font) (Lato / Noto CJK measured at the indicator's 16-21 px plus 36 px
  padding: en 503-593, de 541-644, nl 581-701, pl 560-666, ko 396-444 px; even five took 405-613 px), so the tab
  indicators are base icons (24 px) with the tab name as tooltip: 6 x 60 = 360 px (docs/ui-guide.md "Window").
  Icons: star (Subjects), camera, eye (Views), play (Tour), sun (Light), rain cloud (Weather), all from gui.zip
  paths the base game references. No CSS rule added (tab icon size inline).
- Files: `tools/gen_photo_looks.py`, `content/environments/` (136), `pm_looks.lua` (SKY_ORDER, WATER_ORDER,
  lookKey, lookResName(c, sky, water), parseOurs), `gui/pm_weather.lua` (setLook(sky, water), setLayer, status
  sky / water, looks() a table or nil), `gui/pm_sky.lua` (look(sky, water), layer), `gui/pm_window.lua` (tabs,
  lightTab, weatherTab, layerRow), tests (test_looks, test_window), strings.json (15 new keys, 8 dropped),
  description.html, docs/ui-guide.md, docs/findings/environment.md (+ index).

## Soft background sky look (built after round 11, untested: TESTING.md K20)

User: "push the soft background look really extreme for close up photos of a subject with bokeh background".

- A seventh sky look, **Soft background** (`soft_background`, between Storybook and Moonlit night): no depth of
  field exists, so it fakes a blurred background with the aerial perspective, which only grows with distance along
  the view ray. Extinction ~3 per km for a low camera: a subject 30-60 m away keeps 84-92 % of its contrast, half
  is gone at 200 m, ~95 % at 1 km, into a bright (no mie absorption), near-white veil that glows towards the sun
  (miePhaseG 0.45). Values, shader citations, ranges and caveats: LOOKS.md "Soft background".
- One strength only (a milder one overlaps Hazy morning / Misty valley). Files: 4 x (8 x 5 - 1) = **156, 677 KB**.
- Framing: the Eye level (25 m) and Low angle (60 m) shots and the subject framings (person 22 m, road vehicle
  40 m) already suit it; a dedicated "portrait" preset (e.g. 30 m, level, on the subject) is a possible extra,
  not built.
- Files: `tools/gen_photo_looks.py` (SKY entry, RANGES for the two `*Overcast` mie scales),
  `content/environments/` (+20), `pm_looks.lua` (SKY_ORDER), `gui/pm_window.lua` (SKY_TEXT), strings.json (2 keys x 12
  languages), tests (test_looks, test_window), description.html, CLAUDE.md, LOOKS.md, TESTING.md (K18, K20).

## Round 12 looks (built 2026-10-14, untested: TESTING.md K21-K25)

User (screenshots of the Dry map, a canyon from ~100 m up, session `2026-10-14_0229_sqrl-sqst`: Soft background
switched with the live cloud cover at 0.78 / 0.7, at 12:00 and 05:42): with Soft background "the whole scene
beyond ~50 m is a heavy grey-brown murk, the sky a dull grey-mauve overcast"; "Is it possible to mix Dramatic sky
and a new selector for haze? Or a separate soft selection?"; "Let's also try a soft foreground."

- **Three layers** (LOOKS.md "Round 12"): the atmosphere is split into a **sky** layer (sun disc, bloom,
  brightness, sunset glow, Rayleigh and ozone, the `light` grade) and a **haze** layer (every mie field and
  `fogScaleLow` / `High`); water stays. Sky: Original, Soft light (new: round 11's Misty valley and Soft background
  grade), Dramatic (+ Crisp & clear's deep blue: Rayleigh x1.3, ozone x1.6; its mie went to the haze), Storybook
  (its rosy mie dropped), Moonlit night. Haze: Original, Crisp & clear, Hazy morning, Misty valley, Soft
  background (the old looks' mie and fog parts, names and translations kept). Water: Original, Mirror water,
  Crystal clear, Wild water (Stormy sea merged into it, its overcast light came along). Dropdowns Sky, Haze, Water.
- **File count**: 4 climates x (5 x 5 x 4 - 1) = **396 files, 1858 KB** (was 156, 677 KB). The straight split
  (7 skies x 5 hazes x 5 waters) would have been 696; the cut: Hazy morning's and Misty valley's skies (warm /
  cool grades without their haze) folded into Soft light and the haze looks, Crisp & clear's deep blue (Rayleigh,
  ozone) into Dramatic (its +0.25 contrast and cool ambient dropped: Dramatic has more), Stormy sea into Wild water (both rough, foamy, murky water). No combination is left
  out, so the dropdowns need no rules. The generator's disjoint-field check now covers three layers (each field
  has one owner layer) and passes; test_looks checks each of the 192 files with all three layers set (4 climates
  x 48) against its three single-layer files.
- **Soft background retuned** (model in LOOKS.md "Round 12"): the aerosol packed near the ground (scale height
  2.0 -> 0.4 km, scale 0.25 -> 0.27), phase g 0.45 -> 0.1, fogScaleHigh back to the climate's (was 1), Rayleigh no
  longer x0.6 (the sky layer owns it), the grade moved to the Soft light sky. Camera 100 m above sea level, level
  view: veil at 50 / 100 / 200 / 500 / 1000 m 13 / 25 / 43 / 76 / 94 % -> 6 / 11 / 21 / 44 / 68 %; the sun at 10
  degrees keeps 74 % of its red light (was 24 %); the sky 20 degrees up, away from the sun, blue/red 1.6 -> 3.2
  (climate 4.6); the far veil sideways to a 10-degree sun 0.37 -> 1.3 times a sunlit surface (bright, not grey).
- **Misty valley fixed**: scale height absolute 0.3 km with mie 0.9 (round 11's x0.35 left ~27 % of x10 at sea
  level), no absorption, the same under clouds, phase 0.35: 22 % -> 62 % veil at 500 m.
- **Soft foreground: not built.** The shaders can't make it (LOOKS.md "Soft foreground", findings environment.md):
  transmittance along a view ray only falls, so any haze in front of the subject veils it too; a density rising
  with height would need a negative `mieScaleHeight` (outside the wiki's 0-100, the engine's conversion to
  `mieDensityExpScale` is not in the files) and would fill the whole sky column (or overflow) rather than the air
  near the camera; a cloud layer at the camera's height veils everything behind it as well.
- Files: `tools/gen_photo_looks.py` (SKY / HAZE / WATER, LAYERS, three-layer check, `miePhaseGOvercast` range),
  `content/environments/` (396), `pm_looks.lua` (LAYERS, HAZE_ORDER, ORDER, SET, lookKey / lookResName(c, sky,
  haze, water), parseOurs), `gui/pm_weather.lua` (setLook(sky, haze, water), setLayer for three layers, status
  haze), `gui/pm_sky.lua` (look(sky, haze, water)), `gui/pm_window.lua` (SKY_TEXT, HAZE_TEXT, WATER_TEXT, the Haze
  row), strings.json (11 new keys, 9 dropped), tests (test_looks, test_window), description.html, CLAUDE.md,
  LOOKS.md, TESTING.md, docs/findings/environment.md (+ index).

## Round 12 layout (built 2026-10-14, untested: TESTING.md Y1-Y6)

User: "move light angles into their own heading. Season should have 3 options, then a new row, angle 3 options.
Front light should be first"; "High graphics mode should go in a settings tab, same for hide labels and hover";
"Can screenshot and smooth camera and free camera all fit on one row, with the screenshot section right aligned if
possible".

1. **Light tab**: "Season and sun" split into **Season** (Winter sun, Spring sun, Summer sun: low to high sun) and
   **Light angle** (Front light, Side light, Backlight), a grid row of three each. Spring sun is new: day 80, the
   March equinox (`pm_looks.SEASONS.spring`; autumn would give the same sun, so one equinox preset).
2. **Settings tab** (seventh, last): High graphics mode and Hide labels and hover, the same checkboxes, tooltips
   and wiring as in the footer before. Icon: the base gear `::/gui/menu/icons/settings.tga` (48 px @2x, the mod
   settings' icon in `mod_selector_page.tl:1494`). Indicators: 7 x (24 + 36) = 420 of the 424 px inside the
   content's 8 px padding (inferred from the base TabWidget::Indicator padding; Y1 checks).
3. **Footer: one row**, the camera buttons left and the screenshot group right, then the status line (the footer
   lost two rows: shorter for 1080p). Right-aligned with the base horizontal spacer, no new CSS rule:
   `gui_react_util.makeHorizontalSpacer()` is a Component of class `horizontal-spacer`, base `default.css.lua:124`
   `gravity = { -1, 0 }`, used by the base calendar's Environment row (`game_bar_widgets.tl:647-656`: label,
   spacer, ComboBox in a horizontal BoxLayout). That it takes the spare width in our fixed-width box is inferred
   from the base use (Y3). Inline sheets have no `gravity` (api `StyleSheet`), so the spacer is the only rule-free
   way. A BoxLayout never wraps, so Smooth camera and Free camera sit in a FlowLayout box of `FOOT_LEFT_W` 250 px
   and wrap there (two lines) when a language doesn't fit; the screenshot group (natural width) stays right.
   - The word "Screenshot" did not fit: English at the default (17 px) body font needed ~458 px for the row with
     it. The group's label is the base camera tool's camera icon (`::/gui/camera_tool/icons/camera.tga`, 16 px)
     with "Screenshot" as its tooltip.
   - Widths (Lato / Noto CJK, body 14 / 17 / 19 px, button padding 6 + 6 and a 1 px border, gaps 6;
     scratchpad script, estimates within a few px). Left pair at 17 px: en 240, de 239, fr 233, es 227, it 230,
     nl 243, pl 249, pt_BR 228, ko 234, zh 170 (one line); ru 305 and ja 255 wrap. At 14 px only ru wraps; at
     19 px all but ko and zh wrap. Screenshot group: 121-142 px at 14, 130-157 at 17, 136-166 at 19 (ja / zh
     "%d倍" widest): the row is at most 250 + 12 + 157 = 419 px at 17 px; at 19 px ja / zh go ~4 px past 424.
   - Shortened for the fit: it "Telecamera fluida / libera" -> "Visuale fluida" / "Visuale libera" (the base
     game's own "Free Camera" term), nl "Vloeiende camera" -> "Soepele camera" (and the Camera tab note in both).
- Files: `gui/pm_window.lua` (lightTab, settingsTab, TABS, shutterGroup, footer, FOOT_LEFT_W, styles footLeft,
  ICON.shot), `pm_looks.lua` (SEASONS / SEASON_ORDER spring), `gui/pm_sky.lua` (comment), strings.json (4 keys new,
  1 dropped, it / nl camera names), tests (test_window: Settings tab, footer row, light order, 7 tabs; test_looks:
  spring), description.html, docs/ui-guide.md ("Windows": Settings tab, seven tabs; "Right-aligning", footer).

## Round 15 looks (built 2026-10-14, untested: TESTING.md LS1-LS8)

User: "Is it possible to add more looks, and have them changeable with arrows < > and also a picker? Can season, time
of day, and sun direction be sliders?" Details, the shader reasoning and every value: LOOKS.md "Round 15".

- **More looks**: Sky + Golden glow (ozone absorbing blue: golden sunlight, a longer sunset glow, warm fill), Cold
  blue (ozone absorbing red / green: a pale bluish sun, cool fill, half the sunset glow), Faded film (contrast -0.5:
  the tone mapper's saturation follows it, so the colours fade; warm lifted shadows), Neon dusk (ozone absorbing
  green: magenta twilight; deeper Rayleigh blue, sunset glow 7, violet night fill); Haze + Dust storm (a warm,
  blue-absorbing aerosol spread 1.2 km high: an orange-brown veil and sky); Water + Tropical turquoise (tropical's
  depth-colour texture with clearer water). Not possible: noir / black and white, sepia as a grade (no colour-grade
  field, findings environment.md). Not built for the file count: Overcast moody, Sea mist, Smog, Dark / deep,
  Muddy (LOOKS.md table).
- **Files**: 4 x (9 x 6 x 5 - 1) = **1076, 4541 KB** (was 396, 1858 KB); the generated headers lost their intent
  paragraphs (5184 KB with them). Load time: the logs show no measurable cost for 0 vs 396 files (findings
  environment.md); LS2 measures 1076.
- **Arrows**: `<` and `>` beside each look dropdown (Weather tab), wrapping round through Original
  (`pm_looks.stepLook`).
- **Sliders**: the Light tab's Time of day, Season and Sun direction rows are base `builtin.Slider`s between `<` /
  `>` step buttons (the hour steps `<<` / `>>` dropped), the value text after (hh:mm, "21 Jun", degrees). Applied
  live while dragged without a window re-render: `gui/pm_slider.lua` (own react state, `pm_light` throttle at 80
  ms, quiet `pm_sky.setLive`), one final `pm_sky.set` at the release or 400 ms after the last move. Sun direction is
  the absolute sunRotation 0-359 degrees (no compass label: SUN_CAL unverified, K10). docs/ui-guide.md: the Slider
  rule changed ("A value over a wide range"), arrows beside a ComboBox. No new CSS rules (base `Slider!horizontal`).
- Files: `tools/gen_photo_looks.py` (4 skies, 1 haze, 1 water, `sunsetBoostParam` range, shorter headers),
  `content/environments/` (1076), `pm_looks.lua` (orders, `stepLook`), `pm_light.lua` (SLIDER, toSlider /
  fromSlider, dayToDate, the throttle), `gui/pm_sky.lua` (`setLive`), `gui/pm_slider.lua` (new), `gui/pm_window.lua`
  (texts, layerRow arrows, sliderRow, dateText, MONTHS, styles slider / sliderValue), strings.json (30 keys new, 4
  dropped), tests (test_looks +4, test_window +2 and the audit counts sliders), description.html, CLAUDE.md,
  docs/ui-guide.md, docs/findings (environment.md x2, gui.md, index), LOOKS.md, TESTING.md.

## Round 16 settings (built in code 2026-10-14, untested: TESTING.md RS1-RS12)

User: (1) "I want a way to save the settings as a whole in case you press Escape by accident, like 'custom golden
1', 'my dark night' etc. It would be great if that could save safely with the game." (2) "Does the game support
nested tabs (tabs within one of our tabs)?" (3) "Is it possible for looks to have sliders to adjust the fade, or do
they have to be preset?" (4) "Are there any other look styles we could leverage?"

1. **Saved setups** (Settings tab, "Saved setups"): a setup is the whole picture Photo Mode controls: the three look
   layers (or Legacy), the override's time, day, sun direction, cloud cover, cloud base / top, cloud density, the
   freeze, and whether High graphics mode and hidden labels were on. Dropdown of the setups (each item's tooltip:
   its looks, time and date, frozen, HQ), then a grid: Load, Save new (named "Setup N", the name field opens at once;
   the base `FocusTextInputField` as the saved views'), Overwrite, Rename, Delete, Restore last setup; a note.
   - **Where they live**: the game's settings (`AppConfig.mainMenuState["square_photo_mode_setups"]`, settings.lua),
     not the save: a look recipe fits every map, so every savegame has the same setups, and nothing reaches a save,
     so removing the mod can't touch one (findings gui.md "`AppConfig.mainMenuState` holds nested plain tables"). Not
     `mainMenuState["square_photo_mode"]`: the high graphics marker is written and cleared there as a whole. At
     most 30 setups, names at most 40 characters (the saved views' rules), ~10 KB. Written as pm_button writes its
     marker: a copy of the current config with a full copy of mainMenuState (a partial one would wipe other mods'
     prefs; unreadable = not written, logged once), one `setAppConfig(cfg, false)`, then `saveAppConfig`. From the
     plugin's onStep only, never during a high graphics stage, its restore or a frame that opens / closes a window
     (one setAppConfig at a time, as the stages); while High graphics mode is on the write is not saved (settings.lua
     would get the boosted graphics): the high graphics restore saves a copy of the current config, setups
     included. A write waiting at the pause menu goes out there, after the high graphics restore.
   - **Load**: the look first (one environment switch, the live values carried over), then the values (pm_sky.set:
     the override begins, one log line, the marker saved), the freeze both ways, High graphics mode and hidden labels
     only switched on, never off (the switch stalls ~1 s). On an unknown climate the look part is left out.
   - **The accidental Esc**: Esc opens the pause menu, which puts everything back at once (the look, the override's
     values, the freeze, High graphics mode, hidden labels: "Exit" in Design; findings gui.md "Quitting runs no
     react.onUnmount"). The plugin now keeps the picture as the **last setup** first (`openPauseMenu`, before any
     restore), and an untick of the override does the same; every click that changes the picture updates it too
     (pm_sky.noteChange: a value, a look, the freeze; not the restores, not a slider's live writes). The last setup
     keeps the override's values only when the override was on (a look alone comes back without starting it). It
     sits in our GUI save data (field `last`, written with the views and markers), so it survives a save and reload
     of that game. After the pause menu the status line says "Settings > Restore last setup brings this picture
     back."; the button applies it.
2. **Nested tabs**: possible, the base does it (construction menu, town window, debug view), but every inner
   TabWidget there has rules of its own, unstyled each level adds the 8 px page padding and a frame, and the 7 icon
   tabs already fill 420 of 424 px (findings gui.md "Nested TabWidgets"). The setups fit one column, so they are a
   section of the Settings tab (no rule added); the tab stays short (~300 px at the medium font, inferred).
3. **Sliders for a look's strength**: not live. Only `Environment.AthmostphereParams` (cloudCoverage, cloudBase,
   cloudTop, cloudScattering, dayOfYear, sunRotation) can be set at runtime; every look field is per env file
   (findings environment.md). A strength would be more files: LOOKS.md "Round 16" has the counts (Haze at 50 / 100 %:
   1976 files, 8.3 MB; three steps 2876; four 3776). The load-time logs show no cost for 0, 396 and 1076 files
   (`2026-10-14_0733_session`: 5.62 s enter game with 1076) but nothing past that, and the user's budget is ~1,000
   files / ~5 MB (round 15), already reached: not built. Built instead, live and without files: the Weather tab's
   Adjust rows are three sliders (gui/pm_slider.lua, as the Light tab's): **Clouds** 0-100 % (the old step row; rain
   from ~80 %, findings environment.md "Rain"), **Cloud height** 100-4000 m (cloudBase; the top follows at the
   deck's thickness, `pm_light.sliderChanges`), **Cloud density** 10-400 % of the engine's 0.005 (cloudScattering,
   new to the override's fields: snapshot, restore, marker). The step buttons beside them move one slider step. A
   slider's live writes no longer send the sim's cloud cover (the final set does).
4. **Other looks**: the base `<climate>_old.env` "(Legacy)" atmospheres as a whole look, **Legacy**, last in the Sky
   menu: switched to as they are (no file of ours; ResName `::/climates/<c>/<c>_old.env`, inferred), they bring
   their own haze and water, so a haze or water pick ends Legacy (`pm_weather.setLayer`). The game start also
   switches back when a look of ours (Legacy included: its name ends " (Legacy)") is still rendered or the module
   state still holds one. And `light.globalEmissiveScale` (window and lamp glow, findings environment.md) added to
   two night skies: Moonlit night x2, Neon dusk x2.5 (the same 1076 files, 240 rewritten). Researched, not built:
   LOOKS.md "Round 16".

- Files: `pm_setup.lua` (new), `gui/pm_setups.lua` (new), `gui/pm_button.script.lua` (setups wired: start,
  onStep flush, pause-menu capture / flush / status, hqOn / hqSwitchOn), `gui/pm_sky.lua` (cloudScattering read /
  set, `noteChange` / `beforeRestore` hooks, quiet live cloud writes, `look(..., why)`), `pm_light.lua`
  (cloudScattering field, SLIDER cloud / cloudBase / cloudScattering, `sliderChanges`, SCATTERING, DECK),
  `pm_looks.lua` (WHOLE, MENU, isWhole, Legacy names), `gui/pm_weather.lua` (whole looks, the menu, noteChange, the
  start's own look), `gui/pm_window.lua` (Settings tab setups, cloud slider rows, cloudStep, Legacy and the two
  night tooltips, `last` in the save data, `setups.version`), `tools/gen_photo_looks.py` (globalEmissiveScale),
  `content/environments/` (240 rewritten), strings.json (41 keys new, 2 changed), tests (test_setups new,
  test_window +1, test_button +1, test_looks updated), description.html, docs/findings (environment.md x3 and the
  load row, gui.md x2, index), docs/ui-guide.md, LOOKS.md, TESTING.md (CLAUDE.md's gen line already says 1076).

