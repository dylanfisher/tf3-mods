Status: runs A and B done (2026-10-12, Q1 and Q2 yes, results in docs/findings/map-camera.md "Graphics settings from a mod"); Q3 partly (values left set get saved); quit to the main menu runs no onUnmount; run C done 2026-10-13 (pause-menu restore works for every quit path; Force Quit and Steam stop open the pause menu too, so the safety net stays untested and is accepted as is); run D done 2026-10-13 (tier writes stick, no visible difference: findings/map-camera.md "Geometry tiers"). Runs A-D finished.
Runs E (Photo Mode phases 2-4) built 2026-10-12; first run 2026-10-13 (`2026-10-13_0339_sqpq`): T1 and T2 done
(findings/map-camera.md "Screenshots", "Hiding the game UI"), T3 crashed the game and was removed. Second run
2026-10-13 (`2026-10-13_1924_sqpq`): T6 (live environment edits), T7 (a mod env file, rendering-only switch) and
T9 fov / roll / fade (cutscenes from a mod) run, results in `docs/findings/environment.md`; T4, T5, T8, T9 attach
and T10-T12 not run. Runs F (camera effects: cutscene camera, atmosphere extras, bloom / HDR keys, shader override) built
2026-10-12; of them only T9 (above) has run.

# Testing: Photo Quality probe

Question: can a mod raise graphics quality for a temporary "photo mode" and put it back afterwards?

- **Q1** Can a mod GUI script call `api.util.getAppConfig` / `setAppConfig`? (Only the settings page does it in
  the base game: `base/content/gui/menu/settings_page.tl:1395-1407`.)
- **Q2** Does `setAppConfig` apply the graphics keys (shadows, SSAO, SSR, MSAA, geometry, terrain, grass,
  resolution scale, textures) mid-game, and how long does it stall?
- **Q3** `setAppConfig` does not save. Does the game save the boosted values anyway (settings page on close,
  quitting)? If so, a real mod has to restore before every save path.
- **Q4** Can a mod change the geometry tiers in `baseConfig.settings.geometryQualityOptions`
  (`base/content/base/mod.script.tl:146-154`: draw distance and LOD scaling for low / medium / high / camera tool /
  cockpit / camera tool preview), and is the change visible?

Mod: `mods/square_photo_quality_probe/` (DEV, never upload; `make link` puts it in staging). Every line starts
with `[SQPQ]`. After each run: `make logs-grep PAT='\[SQPQ\]' ARGS='--session last'`.

## Setup

- **Before anything:** screenshot or write down your Graphics settings page. Run C may overwrite them.
- Any save; runs A-D write nothing into it (runs E: a throwaway save, see "Runs E"). Settings shown when the mod is enabled:

  | Setting | Values (default **bold**) | What it does |
  |---|---|---|
  | Boost textures too | **Yes** / No | the boost also sets texture quality to Very High |
  | Restore at pause menu | **Yes** / No | restore when the pause menu opens (No: only the next load restores) |
  | Camera tool LOD scaling | **Unchanged** / 10 / 20 | camera tool tier `lodDistanceScaling` (base 5.0) |
  | Camera tool draw distance | **Unchanged** / 40 km | camera tool tier far plane (base 22.5 km) |
  | High tier | **Unchanged** / Camera tool | High tier gets 22.5 km and LOD 5.0 |
  | Camera tool preview LOD | **Unchanged** / 5 / 20 | camera tool preview tier `lodDistanceScaling` (base 1.0) |

- **Buttons** in the top-left mod button row: "SQPQ boost off" toggles boost on / off (runs A-D); "SQPQ tests"
  opens the runs E window.
- Best with your own settings below Very High, so the boost is visible.

## What the probe logs

| Line | When | Answers |
|---|---|---|
| `load preRunFn before/after ... tiers ...`, `load postRunFn readback ...` | at load | Q4 (write sticks?) |
| `gui start`, `start config ...`, `tiers ...` | first frame | Q1 (read works), Q3 (what the game started with) |
| `boost before ...`, `boost want msaa=...`, `boost on setAppConfig ms=... readback ...` | click on | Q1, Q2 |
| `boost marker ... saved=true`, `boost off(click / pause menu) ... saved=true` | click, Esc | Q3 |
| `pause menu opened`, `marker none` / `marker found: restoring ...` | Esc / game start | Q3 |
| `frames boost=on/off n= meanMs= p95Ms=` | every 5 s | Q2: heavier settings should cost ms per frame |
| `config changed outside the probe: ...` | any other change (settings page) | Q3 |
| `unmount ...` | never seen on quit | - |
| `... ERROR ...` | any failure | Q1 if it is `setAppConfig` |

## Runs

**A. Toggle (Q1, Q2).** Defaults. Load the save, park the camera on a busy town, wait 15 s. Click boost on, wait
15 s, look (shadows, anti-aliasing, grass), click off, wait 15 s. Report what changed on screen and whether the
game hitched on each click.

**B. Settings page while boosted (Q3).** Boost on, open Esc > Settings > Graphics: does it show Very High /
Custom with the boosted values? Close it without changing anything, click boost off, quit to the main menu,
reopen Settings: are your original values there? (The page saves on close, so they may now be the boosted ones.)

**C. Pause-menu restore and safety net (Q3, rev 1 update 2026-10-13).** Quitting runs no `onUnmount`
(first run C, `2026-10-13_0040_sqpq`: settings stayed boosted in the main menu), so the probe now restores when the
pause menu opens and keeps a marker in `AppConfig.mainMenuState` for the next load.
- C1, defaults: boost on, press Esc. Expect `pause menu opened boost=on`, `boost off(pause menu)`, a ~1 s hitch.
  Then Quit > Return to Main Menu; Settings > Graphics should show your own values. Repeat with the burger button.
- C1 done 2026-10-13 (`2026-10-13_0053_session`): restored on Esc, menu button and Cmd+Q (Cmd+Q opens the pause menu).
- C2, safety net: boost on, then force quit (Cmd+Option+Esc > Force Quit, or `pkill -9 TransportFever3`; Cmd+Q
  only opens the pause menu). Start the game: the main menu still shows boosted values.
  Load a save with the probe: expect `marker found: restoring ...`, and your values back in Settings.

**D. Geometry tiers (Q4).** "High tier: Camera tool", Geometry setting High. Compare the far distance and pop-in
of trees / buildings with and without it (two loads, same camera spot). Then "Camera tool LOD scaling: 20" and
"draw distance: 40 km", open the camera tool (AltGr+Z): more detail far away than at defaults?

## Runs E (phases 2-4)

One session answers the open Photo Mode questions. Window: "SQPQ tests" button > "DEV SQPQ tests (runs E)", one row
per test; its last 4 log lines show at the bottom. Code: `content/sqpq/sqpq_tests.lua`. Every line is
`[SQPQ] T<n> ...`; read them with `make logs-grep PAT='\[SQPQ\] T' ARGS='--session last'`.

**Safety.** Use a throwaway save (or don't save during the run). Every test puts back what it changed: its
restore button, its own timer, and "restore all" on Esc (pause menu, `T* restore all (pause menu)`). Saving or an
autosave **while** a T4 / T5 / T6 / T7 change is active keeps it in the save: the time-of-day cycle left on Custom
(T4), the game paused (T5), the weather cycle left on Custom (T6), or with T7 "(+ game)" the save's environment
pointing at this probe's `sqpq_test.env` (a save that then needs the probe). Defaults otherwise; the boost (runs
A-D) can stay off.

Start: load the save, park the camera on a town with some sky in view, wait 10 s, open the tests window (logs
`T* tests window open; AppConfig.cameraTool=... time=... speedup=...`). Order below; wait for each step's +N s line.

**T1 screenshots.** Click "scale 1" (primer: the first request of a session writes no file), wait 3 s, then
"scale 2", 3 s, "scale 3", 3 s, "scale 4", 3 s, then "burst 1,2,4" (three shots 3 s apart), then "clean shot"
(UI hidden, scale 2 after 1 s, UI back after 3.5 s).
- Lines: `T1 screenshot scale=N ... at us=... viewport=WxH ok=true`; the game's own `Screenshot: wrote <path>`
  should follow each (none = dropped).
- Check every PNG in userdata `screenshots/` (newest `<date>_img_<n>.png`):
  `sips -g pixelWidth -g pixelHeight <file>`. Expect viewport x scale (scale 4 may fail or be capped: note it).
  Look whether the UI (game bar, probe window) is in the image for the plain shots and gone in "clean shot".

**T2 hide UI.** Click "b gamebar", "a ui-root class", "d ui-root setVisible", "c free camera" one at a time; each
comes back after 5 s. If the UI is still gone after ~7 s press Esc (restore all), else Cmd+Q (opens the pause menu).
- Lines: `T2 <v> before visible(own/recursive) ...`, `T2 <v> <call> ok=...`, `T2 <v> +1 frame ...`,
  `T2 <v> +1 s onStep still runs while hidden ...` (missing = plugin steps stop while hidden),
  `T2 <v> restored (timer) ...`; for c also `T2 c freeMouseAttached=...`, `T2 c +1 s ...` and, if the game bar was
  still hidden, `T2 c fallback leaveFollowCameraCockpit ...`.
- Look: what disappears per variant (game bar only, all windows, HUD icons / labels on the map, the top-left mod
  buttons), does the 3D view stay, does the camera move (c).

**T3 grid (REMOVED 2026-10-13: crashed the game, see findings/map-camera.md "Full-screen overlay Window crashed").** Click "grid on / off". Expect two vertical and two horizontal thin white lines at thirds over the
whole screen. Try clicking, dragging and scrolling the map through it. Click it again (or wait 60 s) to close.
- Lines: `T3 camera.getSize=WxH`, `T3 grid open (first ...)`, `T3 grid content at screen fractions x a..b y c..d
  (covers w x h)`, then either `T3 grid fits the screen` or `T3 refit: ...` + `T3 grid open (refit)` + a second
  `content at` line, `T3 grid closed (...)`. `T3 grid content got mouse-over (NOT mouse-transparent)` = the grid
  catches the mouse.
- Look: lines at the thirds? any window frame, title tab, shadow or close button visible? map clickable through it?

**T4 time of day.** Note the cycle in the calendar widget. Click "golden hour 18:30", wait 5 s, look; "noon";
"night 23:00"; then "restore".
- Lines: `T4 saved for restore: time=... mode=...`, `T4 golden before time=... mode=...`, `T4 golden sent ...`,
  `T4 golden +1 frame time=18:30:00 ... mode=Constant`, `T4 golden +5 s ...` (time still 18:30 = held),
  `T4 restored (click) time=... mode=...`, `T4 restore +5 s ...` (mode back to the original).
- Look: light changes at once or eases? Calendar widget shows "Custom" while set and the original after restore?

**T5 pause.** Click "freeze / unfreeze", watch vehicles and the game bar speed buttons, click it again.
- Lines: `T5 freeze before speedup=N`, `T5 freeze +1 frame speedup=0`, `T5 freeze +2 s ...`,
  `T5 unfreeze (click) back to speedup=N`, `T5 unfreeze +2 s speedup=N`.

**T6 environment live edits.** Note the weather cycle in the calendar widget. With the weather mode as is: "cloud
0", wait 3 s, "cloud 0.3", "cloud 0.48" (rain?), "cloud 0.48 cmd", "winter (15)", "summer (172)", "sun +pi/2",
"sun +90" (one of the two units should turn the sun ~90°). Then "weather Constant" and repeat "cloud 0.48" and
"winter (15)". Finally "restore".
- Lines: `T6 saved for restore: weatherMode=... worldCloud=... env name=... cloudCoverage=... dayOfYear=...
  sunRotation=...`, per edit `T6 <edit> before ...`, `T6 <edit> set ok=true immediately ...`, `+1 frame`, `+3 s`
  (a Dynamic weather pulls cloudCoverage back toward its target; compare `worldCloud` with env cloudCoverage),
  `T6 sent CloudCoverage SetMode weatherMode=Constant`, `T6 restored (click) ...`.
- Look: clouds / rain, season look (snow, foliage) for dayOfYear, sun direction and shadows for sunRotation.

**T7 environment resources.** Click "list" (one `T7 env getAll(false|true) id=... resName=... name=...
isToolEnvironment=...` line per environment, then `T7 getAll(...): N environments`). Then "SQPQ test (render
only)": strong warm, bright, high-contrast look expected; `T7 find(<candidate>) -> id` lines show which ResName form
matched, then `T7 matched ResName=...`, `T7 switched (rendering only) ... now resName=...`, `T7 +3 s ...`. Click
"switch back" (`T7 switched back (click) ...`). Then "SQPQ test (+ game)", look, "switch back" (auto after 30 s).
- If no candidate matched: `T7 SQPQ test env not found ...`; the getAll(true) lines show whether the mod env is
  registered at all and under what name.
- Look: does the switch change the light at once, does "switch back" restore the original look exactly (clouds,
  time of day light)? Does `resName` change only with "(+ game)"?

**T8 camera tool.** The probe logs `T8 cameraManagerWindow visible nil -> false (AppConfig.cameraTool=...)` at
start and on every change. Open the base camera tool (game bar camera button, if offered), close it, then click
"open camera tool" and "close".
- Lines: `T8 cameraManagerWindow visible false -> true ...`, `T8 open: AppConfig.cameraTool=... visible
  before=false`, `T8 setVisible(cameraManagerWindow, true) ok=... visible after=...`, `T8 closed (click) ...`.
- Look: does the probe's "open" show the camera tool window even with Camera Tool off in the settings?

**End.** Click "restore all", press Esc (`T* restore all (pause menu)` only appears if something was still
changed), quit without saving. Report: the PNG sizes, what each T2 variant hid, T3 fit / mouse result, and the
look for T4, T6, T7.

## Runs F (camera effects)

Can a photo mode get film-camera effects (field of view, roll, fades, a camera that rides a vehicle), stronger haze
and bloom, or a custom tone mapping? Same window ("SQPQ tests", now "DEV SQPQ tests (runs E, F)"), rows T9-T12.
Same rules as runs E: throwaway save, every test puts back what it changed, Esc runs "restore all". Read the
lines with `make logs-grep PAT='\[SQPQ\] T(9|1[0-2])' ARGS='--session last'`.

**T9 cutscene camera.** `api.gui.mission.playCutscene(filePath, resolveLanguageFolder, entityToEntityMap)`
(`api/gui.d.tl:750-761`) plays a keyframe file like the campaign cutscenes. The probe ships
`content/mission/keyframes/sqpq_{fov,roll,fade,attach}.lua` plus identical copies under `keyframes/en/` (the
campaign calls `<mod>::/mission/keyframes/X.lua` with `resolveLanguageFolder = true` and keeps the files only in
`en/` and `de/`). Keyframe positions are absolute world coordinates, so the files compute their frames when
`data()` runs: from `_G.SQPQ_T9` (the camera, set by the probe right before the call; seen only if the file runs in
the GUI Lua state), else `api.gui.camera` (if that state has it), else a spot 400 m above the map origin (then the
cutscene looks at the wrong place: that is an answer too). Before playing, the probe fires `clearToolStack` and
`disableToolActions` like the base cutscene task (`mission/tasks/cutscene/cutscene.tl:35-40`); after the end it
re-enables tool actions, puts the game speed back if the cutscene changed it, and 0.5 s later puts the camera
back (`setCameraData`). There is no stop function in the API docs; each test ends by itself in 5-6 s.
- Park the camera on a town, 200-500 m away, some sky in view. Click "ug_require file" first (loads the file
  the way the dialogue overlay does, `mission_react_util.tl:264-267`): `T9 file(fov in keyframes/) chunk loaded:
  api=table api.gui=... SQPQ_T9=...` (missing = it isn't Lua with logging here), `data() call 1 origin=...`,
  `T9 ug_require(...) ok=true -> function; data() -> 3 camera frames ...` for both copies. Click it again: a second
  "chunk loaded" line = no cache, only "data() call 2" = cached chunk.
- "play FOV test" (path form A): expect a zoom from wide (fovY 1.0) to tele (0.3) over 4 s from the current view.
  Lines: `T9 fov before: playing=false ...`, `T9 SQPQ_T9 set=true pos=... angle=... (camData angle=...)`,
  `T9 fov playCutscene(square_photo_quality_probe::/mission/keyframes/sqpq_fov.lua, true) form A returned
  ok=... ms=...; immediately playing=...`, the file's own `T9 file(fov in keyframes/en/) chunk loaded ...` and
  `data() call N origin=<global SQPQ_T9 | api.gui.camera | fallback ...>` (which copy and which source = how
  the engine loads keyframe files; no file line at all = it reads them without our logging, e.g. another state
  with no `log` and no `print`), then every 0.5 s `T9 fov +N s playing=true elapsed=... speedup=... ui-root=...
  eye=...`, then `T9 fov end (isCutscenePlaying went false) ...`, `game speed ...`, `+0.5 s after end ...`,
  `camera put back (eye had moved N m ...)`. `never playing after 3 s` = the call did nothing for this form.
- Then "play roll test" (horizon tilts ~14 degrees) and "play fade test" (fade in from black, dip to black at
  ~3 s). If form A never plays, click "next path form" (B: `.lua` without language folder, C: no `.lua` with
  language folder, D: neither) and repeat "play FOV test" for each.
- "play attach test": select a moving train or bus, click its follow-camera button, then click. Expect a view 30 m
  behind and 8 m above it, riding along and sliding sideways. Lines: `T9 attach: entityToEntityMap { [1] = N }
  (carriage 1 of followed vehicle M)` or `attach: follow a vehicle first ...`.
- "api members" lists everything in `api.gui.mission`; "stop" calls any stop / skip function found there (also
  tried by itself if a cutscene still plays after 20 s). If the UI or tools stay locked after a test: Esc.
- Look: did the camera move to the view we asked for, or somewhere else (wrong angle convention: compare the
  `angle`/`pitch` we computed with `camData angle/pitch`)? Is the game UI hidden or still there while it plays,
  do the frames ease or jump, does the game pause (`speedup=` while playing), black bars, a skip hint? Does the
  camera come back by itself at the end (`eye had moved` near 0) or only after our put-back? Esc during a test
  should end it (`T9 ... end (pause menu)`).
- If any form crashes the game, note which (the last `T9 ... playCutscene(...)` line names it) and stop.

**T10 atmosphere extras.** Fields the `Environment` typedef doesn't list (`type.d.tl:5326-5343`) but the
environment files have: "read fields" logs `T10 read fogScaleLow=... sunBloom=... miePhaseG=...` (values, nil or
`ERR` = not exposed) and which other members (`light`, `water` ...) the live Environment has. Then, 5 s apart and
looking at the horizon and the sun: "fog x3", "sunBloom 50" (base 350), "sunBloomScale x3", "miePhaseG 0.9",
"mieScattering x3", then "restore".
- Lines per click: `T10 <edit> before ...`, `T10 <edit> setEnvironment ok=... <field> written | write ERR ...;
  immediately ...`, `+1 frame`, `+3 s ... (still the written values = it sticks)`, `T10 restored (click) ...`.
- Look: more haze / fog in the distance, a bigger or brighter glow around the sun, then everything back after
  restore.

**T11 AppConfig dev keys.** `bloomQuality` (1 in the user's settings.lua) and `useLegacyHdr` (false), not on the
settings page. One `setAppConfig` per click and only one changed key at a time (clicking the other key logs
`restore <key> first`), because a many-key switch crashed the renderer twice (findings/map-camera.md "Graphics
settings from a mod"). Click "bloom 0", look 5 s, "bloom 2", look, "restore"; then "legacyHdr true", look,
"restore". Wait for the `+1 s` line between clicks.
- Lines: `T11 saved for restore: bloomQuality=1 ...`, `T11 set bloomQuality=0 setAppConfig ok=... ms=...
  readback ...`, `+1 frame`, `+1 s`, `T11 restore(click) bloomQuality=1 ...`.
- Look: bloom around bright lights and the sun (0 = none?), the overall tone of the picture with legacy HDR (the
  base `compose.fs` switches to an old filmic curve and drops the contrast settings), any hitch.

**T12 shader override (opt-in).** A mod.json param can't add or remove a file, so the test shader lives in its own
DEV mod, `mods/square_shader_override_probe/` ("DEV Shader Override Probe", `make link` stages it): a copy of
the base `rendering/programs/shaders/hdr/compose.fs` that mixes 35 % magenta into the final image. Enable it in the
mod list for the test save only (next to the photo quality probe), load, and look before clicking anything: a
magenta 3D view = the file replaced the base shader at load. Then click "check + instructions" (`T12
square_shader_override_probe active=true ... AppConfig.debugMode=true`) and press **AltGr+R** (shader reload,
needs debug mode, the user's settings.lua has `debugMode = true`; on a Mac keyboard AltGr is probably the right Option
key). Look for the tint, check stdout for shader compile lines. Afterwards disable the mod again (a save loaded
with it while it works stays magenta).
- Results to report: tint at load yes / no, after AltGr+R yes / no, any shader error lines, a crash.

**End.** "restore all", Esc, quit without saving, disable DEV Shader Override Probe. Report per test: what moved on
screen (T9 per form and mode), which T10 fields stuck and showed, the look of bloom 0 / 2 and legacy HDR, and T12.
