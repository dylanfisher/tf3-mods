Status: first in-game run 2026-10-13 (`2026-10-13_0325_session`: 1, P1, P3, P5-P8, P10, P11 partly seen); the
graphics switch crashed twice (`2026-10-13_0342_sqot`, `2026-10-13_0356_top-up-779299`) and was redesigned the
same day; second run `2026-10-13_0418_session`: F1's staged switch on worked 4 of 4 (no crash; every one-call
restore logged 2x "Could not invert matrix"), F4, F5 (add / rename / delete), F6 and F8 seen. The second feedback
round (PLAN.md "Rev 1 feedback round 2") is built, untested: run G1 and G2 first, then G3-G10 and S1-S12
(2026-10-13). Since round 2 the toggle is the "High graphics mode" checkbox in the window's footer: read
"Highest graphics" in the older checks below as that checkbox. Round 3 (PLAN.md "Rev 1 feedback round 3",
built 2026-10-13, untested) after two more crashes on the shadow stage (`2026-10-13_0522`, `_0524`): High
graphics mode never touches shadows, so the switch has **4 stages** (textures, detail, SSAO / reflections,
MSAA / scale); read every `N/5`, "5 stages" and `shadowQuality` stage below as the 4-stage version. Run G11
first (window, spacing, footer, Hide UI), then G1, G2, G3h. Round 4 (PLAN.md "Rev 1 feedback round 4" and
"Phase 3: Light & weather", built 2026-10-13, untested): run G20 first (the way back from a hidden UI), then
G16-G19 and L1-L9. Round 5 (PLAN.md "Rev 1 feedback round 5", built 2026-10-13, untested) after a crash on the
geometry / terrain / grass stage (`2026-10-13_0558_session-crash`): High graphics mode no longer touches
geometry, terrain or grass either, so the switch has **3 stages** (textures, SSAO / reflections, MSAA / scale);
read every `N/4`, "4 stages" and geometry stage below as the 3-stage version. Run G1, G2 and G12 first, G12 on
the `_0558` desert save. Round 6 (PLAN.md "Rev 1 feedback round 6", built 2026-10-13, untested): run **G22
first** (layout: the spacing of rounds 3-5 never showed), then G23 (camera mode), G21 (labels and hover), G24-G28.
Since round 6 the footer has "High graphics mode", "Hide labels and hover" and a "Camera mode" button (no "Hide
UI" checkbox: read "Hide UI" in G3h, G11, G15 and G20 as the fallback G23e describes), and the Tour tab's "Hide
the game UI during the tour" is "Camera mode during tours" (unticked = the UI root hidden, as the old box ticked).
Round 7 (PLAN.md "Rev 1 feedback round 7", built 2026-10-13, untested): run **R1 first** (the eye no longer
follows the terrain), then R2-R10. Since round 7 the Tour tab's "Lowest view" / "Highest view" are "Angle from"
/ "Angle to", "Closest" / "Farthest" are "Distance from" / "Distance to", "Camera mode during tours" is "Try
camera mode during tours" and **off by default** (read G23b-f with it ticked), and the Mode row has a fifth
mode, "Wander". Round 8 (PLAN.md "Rev 1 feedback round 8", built 2026-10-13, untested; R1b's dz in
`2026-10-13_0856_sqot-dev` was 14-549 m, explained by a pitch offset of the game's camera): run **U8 first** (the
height bumps), then U1-U7, U9-U12. Since round 8 every action button is outlined and compact, the Subjects,
Camera and Light tabs' buttons are grids of equal cells, the Tour tab's Mode is a dropdown, and Camera mode sits
in the footer's row as an outlined button. Round 9 (PLAN.md "Rev 1 feedback round 9", built 2026-10-13, untested; session
`2026-10-13_1755_session`: U8 dz +3.4 to +4.6 m = the centre's 4 m lift, the offset not constant): run **V1 and V2
first**, then V3-V10. Since round 9 the Tour tab has no "Try camera mode during tours" (G23b-f and R6 are obsolete:
tours never use the free camera), the hover is off during every tour, Wander and Orbit, and `cam trace` lines show
`model=` / `res=` instead of `off=` (read U8a's `pitch offset measured` as V2b's `camera model: first sample`). Round 10 (PLAN.md "Rev 1 feedback round 10", built 2026-10-13, untested; session `2026-10-13_1915_session`: V1 failed,
hover and money floaters during tours; V5's Aerials jerky): run **W1 and W2 first**, then W3-W9. Since round 10 the
footer's "Camera mode" is "Free camera" (read it so in G23, R6 and V7) next to a new "Smooth camera", the Camera tab
has a "Smooth camera" section, `eye smoothness` lines end in `cuts= guarded=`, and the camera model numbers in
`cam trace` / `eye check` lines are the refit's. Phase 4 (PLAN.md "Rev 2" item 4, LOOKS.md; built 2026-10-13,
untested): after W1-W9 run **K1 and K2 first** (the look files load and switch), then K3-K13; since phase 4 the
Light tab has the sections Looks, Weather over time, Time-lapse and Season and sun between Presets and Adjust
(read L9 with them). Shutter (PLAN.md "Rev 2" item 2, built 2026-10-13, untested): run **X1-X3 first** (sizes,
primer), then X4-X8; since then the footer has a "Screenshot" row (1x / 2x / 4x) above the status line. Round 11
looks (PLAN.md "Round 11 looks", built 2026-10-14, untested): run **K17 and K22 first** (icon tabs, 396 look files
load), then K14-K16, K19 and K21-K25 (round 12: a Haze dropdown between Sky and Water, Soft background retuned;
K18 and K20 superseded by K22 and K23); since round 11 the tabs are icons (star, camera, eye, play, sun, cloud: the name shows
on hover), the looks are two dropdowns (Sky, Water) on a new Weather tab with the cloud presets, Weather over time
and the Clouds steps, and the Light tab keeps the time presets, Time-lapse, Season and sun and the time / season /
sun steps (read K2-K13 and L1-L9 with that split: a look is now "Sky: X" or "Water: X", "Original look" is the
dropdowns' "Original"; Mirror water and Stormy sea are water looks). Round 13 (PLAN.md "Round 13", built
2026-10-14, untested): run **CB4 first** (the game's Advanced Camera Tool by hand), then CB1, CB3, CB6 and,
with the DEV mod, CB2 (re-run after the mapping fix); round 13 item 5: CB7 (Aerials by default, Look High) and CB8 (what the Down look's jolts are); the Smooth camera is gone (W4, Z2's smooth camera part, CA1, CA4
obsolete); CA6 and CB5 are closed (no `io` in the GUI state). Round 14 (PLAN.md "Round 14", built 2026-10-14,
untested): run **CC1 first** (hover during tours), then CC2 (shots come back), CC4 (Down: the centre fit) and, with
the DEV mod, CC3 (the orbit's pace); use only Photo Mode + its DEV mod (the ~20-mod set hung at load again,
`2026-10-14_0632_sqsg-crash`). Round 18 (PLAN.md "Round 18", built 2026-10-14, untested): run **R18-3 first** (the cutscene bar
and F9 during a Lens view), then R18-5 / R18-6 (the lens on a vehicle, how often it starts), R18-2, R18-7 and, with
the DEV mod, R18-1 (risky graphics: expect possible crashes). Since round 18 the Settings tab's checkbox is "Hide
labels" (read "Hide labels and hover" in older checks as it). Round 19 (PLAN.md "Round 19", built 2026-10-14,
untested): run R19-1 / R19-2 (the lens starts on landscape and 400 mm orbits), then R19-3 (Steady), R19-4
(animals without a limit) and R19-5 (the arrows). Round 20 (PLAN.md "Round 20", built 2026-10-14, untested): run
**R20-6 first** (the game stays running after a lens view), then R20-1 / R20-2 / R20-3 (the Animals tab), R20-4
(horses), R20-5 (a jump follows), R20-7 (slower orbit, DEV mod), R20-8 (telephoto), R20-9 (tabs and texts); R18-1
is gone (the DEV risky graphics were removed).

# Testing: Photo Mode

`make link`, enable Photo Mode. Every log line starts with `[PhotoMode]`; after each run:
`make logs-grep PAT='\[PhotoMode\]' ARGS='--session last'`. Before the first run, write down (or screenshot) your
own Settings > Graphics page, ideally set below Very High so the boost is visible.

## Checks

1. **Highest graphics on / off.** Load a save. The camera button sits in the top-left mod button bar, same size
   as the layers button and our other buttons, two-line tooltip. Click: the window opens, no hitch. Turn
   "Highest graphics" on (top of the window): the stages (F1), the picture gets sharper (anti-aliasing,
   textures; shadows, geometry, terrain and grass stay as set). Log: `hq on: player's settings ...`, `hq on:
   marker ... saved=true`, `hq stage 1/3 ...` .. `hq stage 3/3 ...`, `hq on: 3 stages ms= now textureQuality=2
   ... numMSAASamples=8 ...`. Toggle off: ~1 s hitch, your look is back, `hq off(toggle) after stage 3 of 3: 3
   restore stages` ... `restored in 3 stages` with your values.
2. **Esc restores.** Highest graphics on, then Esc: the pause menu opens, `hq off(pause menu) ...`, ~1 s hitch.
   Close the menu: the toggle shows off, the button has no green contour. Repeat with the game bar's menu
   button and Cmd+Q; and once with the window closed (HQ on, window closed, Esc).
3. **Quit to the main menu.** Highest graphics on, Esc > Quit > Return to Main Menu. Settings > Graphics in the main menu shows
   your own values (not Very High / 8x MSAA). Same with Return to Desktop, then restart the game.
4. **Settings page.** Highest graphics on, Esc > Settings > Graphics: the page shows your own values (the pause
   menu restored them first). Change one value there, close, toggle on and off again: the new value comes back.
5. **Existing save, add / remove.** Add the mod to a save that never had it: loads with no warning. Save, remove the
   mod, load again: no warning, nothing missing. Your graphics values are unchanged throughout.
6. **Safety net.** Highest graphics on, then kill the game (`pkill -9 TransportFever3`; Cmd+Q and Force Quit open the pause menu
   and restore normally). Start the game: the main menu may show the boosted values. Load any save: log
   `marker found: restoring ... | kept -`, and Settings > Graphics shows your values again. Variant: after the
   kill, change Reflections by hand in the main menu, then load: `kept ssrQuality`, your new Reflections stay.
7. **Mod settings.** (Round 21: the Text style is gone.) The mod's settings show only "Debug: performance
   log"; the top-bar button is always the camera icon, also in a save made with the old "Top bar button" = Text.
8. **Other mods.** With Better Minimap or Supply Gaps on as well: `[SQ ridge] layer window offset: skipped in
   square_photo_mode (added by ...)`; with Photo Mode alone: `added by square_photo_mode`, and the data layer
   windows open below the button row.
9. **Map editor.** The button and the toggle work there too, and Esc restores.

## Rev 2 phase 1: the camera window

Use a save with trains, buses, trucks, trams, an airport with flights, a harbour with ships, a road or rail
bridge with traffic, and several towns. Every API below is unverified in game; each check names it.

P1. **Window opens and closes.** Click the camera button: a "Photo Mode" window opens at once (no hitch) at the
   left edge, the "Highest graphics" toggle above the tabs Subjects / Camera / Views; the button stays pressed.
   Close it with X: button released, `window closed by the player`, graphics unchanged. Open again, click the
   button: `window closed (button)`. Esc with the window open: note whether the window stays or closes (Esc may
   close the top window through its onClose, as Better Minimap saw; either is fine).
   (`addSingletonWindow`, `TabWidget`, window position rule `#squarephotomode.window`)
P2. **Layout and translations.** The rows wrap inside the window (no button cut off) in English and in German
   (longest labels); the status line wraps. Every button has a tooltip. Note the window height per tab.
P3. **Random subjects.** Click each of Vehicle, Train, Road vehicle, Aircraft, Ship, Person, Station, Town,
   Industry a few times: the camera lands on such a thing, framed from 15-30 degrees above, a different angle
   each time. Log: `list <kind> n= ms=` (first click; note the ms, especially `persons` and `towns`),
   `jump <kind> (random) entity= kind= view=...`. A kind the map lacks shows a grey line in the window and
   `jump <kind>: none`. (`getEntitiesWithComponent` for TRANSPORT_VEHICLE, MODEL_PERSON (else SIM_PERSON),
   STATION_GROUP, INDUSTRY; `makeMapFromGame`; BOUNDING_VOLUME / CARRIAGE_LIST / MODEL_PERSON positions;
   `setCameraData`; `api.type.enum.Carrier`, `TransportVehicleState.IN_DEPOT`)
   - Check: does the view land on the vehicle itself (a moving train's middle car, a bus) or somewhere stale
     (BOUNDING_VOLUME of a moving vehicle)? Do trains look framed (120 m)? A person (22 m)?
   - If `list persons` logs "MODEL_PERSON not listable", note whether the SIM_PERSON fallback finds walkers.
P4. **Aircraft in flight.** Click Aircraft until one in the air is picked: the camera follows it (log
   `... airborne: follow`). (`followEntity(e, true)`, `getHeightAt`)
P5. **Interesting.** (Round 2 replaced Busiest station, Biggest town, Vehicle on a bridge and Aircraft at an
   airport with S1-S12; only Longest train of this check remains.) Busiest station: lands on the station with the most lines (log `busiest station <id>
   lineStops=N`). Biggest town: the largest town (`biggest town <id> population=`). Longest train: the longest
   running train (`scan longest: read N of M ms= parts=`). Vehicle on a bridge: a vehicle on a bridge, or the
   grey "No vehicle on a bridge right now." (`scan bridge: ... found=`). Aircraft at an airport: one taking off /
   landing, else approaching / taxiing (`scan airport: ... score=3|2|1|0`). Note every scan's ms (budget 35 from the click, list build included).
   Click Longest train a few times on a big save: the scan goes on where the last click stopped and keeps its
   best (round 17: the next clicks show other long trains, the best comes back after its cycle from a new angle).
   (`getStationGroup2LineStopsMap`, `getTown2personCapacitiesMap`, `transportVehicleConfig.vehicles`,
   MOVE_PATH `path.edges[dyn.pathPos.edgeIndex + 1]`, BASE_EDGE type BRIDGE, MOVE_PATH_AIRCRAFT flightState)
P6. **Shots.** After a jump, Camera tab: Eye level, Low angle, Drone, Bird's eye each keep the centre and the
   direction. Log `shot <key> view=...`. Check: does the camera accept pitch 0.04 and 25 m (eye level) or clamp
   it? Does it ease back to another distance within a second? Read the camera after ~2 s (open the window again
   or take a second shot) and note the result. (`setCameraData` pitch / distance limits)
P7. **Orbit.** Toggle Orbit: the view circles slowly (a turn a minute), the toggle stays pressed. Zoom with the
   wheel: orbit stops (`orbit off (camera moved: zoom)`), toggle released. Turning
   with the mouse stops it too (`turn`). Panning alone keeps orbiting around the new centre (by design).
   (`getCameraData` reads back what we set every frame)
P8. **Follow.** Jump to a train, toggle Follow: the camera follows it (`follow on entity=`). Toggle off: see F3
   (first run: `follow off (button)`, but the camera kept following until moved; fixed by the staged release). Orbit while following: circles around the moving train. Follow with no subject yet:
   grey "Jump to a vehicle or a person first." (`followEntity(e, false)`, `getFollowEntity`)
P9. **Cockpit.** Jump to a train, toggle Cockpit: cockpit view (`cockpit on entity=`). Toggle off: back to the
   map (`cockpit off (button)`). Cockpit again, then Esc: the pause menu opens, highest graphics off, cockpit left
   (`cockpit off (pause menu)`). If the game ends the cockpit by itself, look for `stoppedFollowAction`.
   (`enterFollowCameraCockpit`, `leaveFollowCameraCockpit`, react event `stoppedFollowAction`)
P10. **Tour.** (Since round 2: the Tour tab; Ground level mode.) Views tab, 5 s, Start tour: the camera glides (~4.5 s since F7, rising mid-way on long hops) from subject to
   subject of mixed kinds. Log `tour on every=5s`, `tour <kind> (<why>) entity= to=...` every ~7 s. Switch to
   20 s while running: longer stays. Pan the camera: the tour stops (`tour off (camera moved: pan)`), button
   shows Start tour. Start again, then Esc: `tour off (pause menu)`. Note any stutter during glides.
P11. **Saved views.** Save view three times at different places: "View 1/2/3" appear. Go to View 2: exact view
   back. Delete View 1 (trash). Save the game, load it: Views 2 and 3 are there (`bookmarks loaded n=2`). Load
   another save: no views. Save 50: Save view greys out with the "At most 50 views" tooltip. Then remove the
   mod and load the save: no warning (GUI save data of a missing mod). (`setGuiSaveData` / `getGuiSaveData`)
P12. **Map editor.** The window opens there too; subject buttons show the grey "none" lines where the map has
   nothing; Town works; no errors.

P13. **Performance log.** Mod setting Debug: performance log = On. Open the window, click a few subjects and
   scans, run Orbit and a Tour for a minute. `make perf ARGS='--mod square_photo_mode'`: `camera_step` max well
   below 16 ms, `pick_*` max below ~50 ms (note `list_persons` on a big save). Then Off: a normal session logs no
   `[SQPERF] mod=square_photo_mode` lines except slow ones.

## Rev 1 feedback (built 2026-10-13, untested; PLAN.md "Rev 1 feedback")

F1. **Staged highest graphics** (the one-call switch crashed twice, `2026-10-13_0342_sqot`,
   `2026-10-13_0356_top-up-779299`; PLAN.md "Highest graphics: the staged switch"). Set your own graphics below
   Very High first (as before: Low-ish, MSAA 1x).
   - *Open = no hitch*: click the camera button: the window opens at once, no stall, no `hq` line, no
     `setAppConfig` (no `Saved settings to settings.lua` line either).
   - *Staged on*: click "Highest graphics": the toggle shows pressed at once, then the hitches come in steps
     over ~15 frames. Log, in order: `hq on: 5 stages, 3 frames apart`, `hq on: player's settings`, `hq on:
     marker ... saved=true`, `hq stage 1/5 keys=textureQuality,terrainTextureQuality ms=`, `hq stage 2/5
     keys=geometryQuality,terrainQuality,grassQuality ms=`, `hq stage 3/5 keys=useSsao,ssrQuality ms=`, `hq stage
     4/5 keys=shadowQuality ms=`, `hq stage 5/5 keys=numMSAASamples,resolutionScale ms=`, `hq on: 5 stages ms=`
     (since round 3: no shadow stage, `hq stage 4/4 keys=numMSAASamples,resolutionScale`, `hq on: 4 stages`).
     **Note each stage's ms** (where the ~1.2-1.5 s went) and whether the stall felt like one hitch or several.
     No crash, no `Could not invert matrix` warnings (`make logs-grep PAT='invert matrix|hq stage' ARGS='--session last'`).
   - *Close keeps HQ*: close the window (button, then once with X): the graphics stay high, no hitch, no `hq
     off` line; the camera button shows a green contour and its tooltip ends "Highest graphics: on.". Open the
     window again: the toggle shows on.
   - *Esc restores*: with the window closed and HQ on, Esc: `hq off(pause menu) after stage 5 of 5`, ~1 s hitch,
     your settings back. Close the menu: no green contour; open the window: the toggle shows off.
   - *Five on / off repeats*: toggle on, wait for `hq on: 5 stages`, toggle off; five times. Every `hq off(toggle)`
     restores your values; no crash.
   - *Cancel mid-sequence*: toggle on and at once off again (within the 15 frames): `hq off(toggle) after stage K
     of 5` with K < 5 (or `hq on cancelled (toggle) before stage 1`), no stage after it, your values back. Same
     with Esc right after the toggle: `hq off(pause menu) after stage K of 5`.
   - *Long session*: play normally for 15+ minutes (build, run time, open other windows; once also after loading
     a second save in the same session, as in `2026-10-13_0356`), then toggle HQ on. This is the case that
     crashed. If it crashes: the last `hq stage N/5` line before the crash names the stage; archive the session
     (`make logs ARGS='--tag pm-crash'`) and keep the minidump.
F2. **Status line.** Click Aircraft on a map without aircraft (or another "none" button): the grey line
   "No aircraft in service." sits under the tabs in body-size text with room around it, inside the window (the
   window grows; nothing overlaps the bottom edge). German: a long line wraps onto two lines inside the window.
F3. **Follow off.** Jump to a bus, Follow on, wait 5 s, Follow off. The camera stops following within a fraction
   of a second and stays where it was (same zoom and angle). Log: `follow off (button) followEntity=<id>`, then
   `follow released by focusPosition (button)` (or `setManualCamera` / `leaveFollowCameraCockpit`): **note which
   call worked**. If `follow still on after every release call`: the status line asks to move the camera; note
   it. Repeat: Follow on, then a subject button (jump): the camera lands on the new subject and doesn't drift
   back (`follow released by ... (jump)`); Follow on, then Go to a saved view; Follow on, then close the window
   (`(window)`) and Esc (`(pause menu)`). (`focusPosition`, `setManualCamera`, `leaveFollowCameraCockpit`,
   `getFollowEntity`)
F4. **Anything.** Click Anything ten times: a mix of kinds (trains and road vehicles more often than people).
   Log `jump any (any <kind>) entity= kind=`. On an empty map (map editor): the grey "Nothing to show on this
   map yet."
F5. **Saved views table.** Save 4 views. Each row: name, Go, up, down, pencil, trash, aligned in one row each;
   the first row's up and the last row's down are greyed out. Pencil on View 2: a text field with the name,
   focused; type "Harbour at dusk", Enter: the row shows the name (`bookmark rename id=2`). Pencil, Esc: no
   change. Pencil, clear the field, Enter: back to "View 2". A very long name: cut at 40 characters, the row
   shows the start with the full name in a tooltip. Move View 4 up twice (`bookmark move id=4 by -1`), Go on
   each row. Save the game, load it: names and order kept. Save more than 8: the list scrolls inside the tab
   (300 px), the window doesn't grow past it. German and Japanese names (umlauts, kana) survive save / load.
F6. **Tour source.** Saved views selected with no views: Start tour shows "Save a view first, or tour random
   subjects." and nothing starts. With 4 views: the tour visits them in list order and starts again after the
   last (`tour on source=views`, `tour view <id> to=`). Reorder during the tour: the next hops follow the new
   order. Delete all views during the tour: it stops at the next hop (`tour off (no saved views)`).
F7. **Tour motion.** Random subjects, 10 s: each hop glides ~4.5 s, smooth start and stop, rising on long hops;
   at each place a slow drift (a slow turn, a little tilt, sideways pan, slight zoom), different per hop, never
   a jerk at the start or end of the hold. With saved views the drift is smaller and stays near the saved view.
   Turn Orbit on during a tour: the drift keeps turning. Note any stutter (`make perf`: `camera_step` max).
F8. **Tour framing.** Random subjects: every place seen from eye level to a little wider than Low angle, never
   from drone or bird's eye height (log `to=x,y,d,a,p`: d 25-90, p 0.04-0.20). Note any subject that looks badly
   framed at that height (a town or industry seen from 90 m, a ship's hull filling the screen).
F9. **modinfo.** Mod list / Mod Hub in English and one other language: the summary mentions the camera window.
F10. **Persons list.** Click Person a few times over a minute: `list persons: MODEL_PERSON not listable ...,
   using SIM_PERSON from now on` at most once per game session (it was logged with a traceback at every list
   build), then plain `list persons n=` lines.

## Rev 1 feedback round 2 (built 2026-10-13, untested; PLAN.md "Rev 1 feedback round 2")

Log lines: `make logs-grep PAT='\[PhotoMode\]' ARGS='--session last'`. After each check: no `ERROR` line from
`[PhotoMode]` (`tab tour render ERROR`, `footer render ERROR` would mean a broken widget).

G1. **High graphics mode checkbox.** The window's footer (under the tab content, on every tab) shows the
   checkboxes "High graphics mode", "Hide labels" and "Hide UI", native checkboxes like the game's settings;
   the High graphics tooltip says shadows, geometry, terrain and grass stay at your setting. Tick "High graphics
   mode": 3 stages (`hq stage 1/3 keys=textureQuality,terrainTextureQuality`, `2/3 keys=useSsao,ssrQuality`,
   `3/3 keys=numMSAASamples,resolutionScale`; no `shadowQuality`, `geometryQuality`, `terrainQuality` or
   `grassQuality` in any `keys=`; Shadows, Geometry, Terrain and Grass in Settings > Graphics unchanged
   afterwards), no "Could not invert matrix", no crash; the box stays ticked;
   close the window: the camera button has the green contour, tooltip "High graphics mode: on.". German: the
   footer wraps inside the window.
G2. **Staged restore.** Untick: `hq off(toggle) after stage 3 of 3: 3 restore stages, 3 frames apart`, then
   `hq restore stage 1/3 keys=numMSAASamples,resolutionScale ms=`, `2/3 keys=useSsao,ssrQuality`, `3/3
   keys=textureQuality,terrainTextureQuality ms= (marker cleared, saved)`, `hq off(toggle) restored in 3 stages
   ms=`. **Note each stage's ms**, and check: `make logs-grep PAT='invert matrix|hq restore' ARGS='--session
   last'` shows **no** "Could not invert matrix" after the staged restore (it followed every one-call restore in
   `2026-10-13_0418_session`). Your settings are back.
   - *Esc during the restore*: tick, wait, untick and press Esc within ~10 frames: `hq off(pause menu, during the
     staged restore) after stage 3 of 3` (one call at once), no `hq restore stage` after it.
   - *Tick again during the restore*: untick and tick again at once: `hq on again during the staged restore`, the
     stages that were already put back run again, the box ends ticked, graphics high.
   - *Esc with it on*: still one call at once (`hq off(pause menu)`), as before; no "Could not invert matrix"
     should follow it now (it no longer changes shadows).
G3. **Hide labels.** On a busy save (town names, station "1/20" rates, passenger counts, vehicle icons): tick
   "Hide labels": log `labels hidden (player's filter kept|absent)`.
   a. Do the labels vanish **at once** (else only after opening / closing a tool or the data layers window: then
      the selector refresh doesn't work; note it)? Which labels stay (town names? the chevrons? line colours?
      notification icons?) Screenshot both states.
   b. Click a vehicle or a station on the map right after ticking: the entity window opens as usual (the
      selector was re-enabled a frame later).
   c. Open the data layers' HUD filter window: every toggle shows off. Untick "Hide labels": `labels shown
      (checkbox)`, your own filter (set one or two toggles off beforehand) is back exactly.
   d. Tick, change one toggle in the HUD filter window, untick: `... the filter was changed meanwhile, kept`.
   e. Tick, then Esc: `labels shown (pause menu)`. Tick, save the game (Esc > Save), load it: labels are back
      (the pause menu restored them before the save). Tick, wait for an autosave (or quicksave with F5 if it
      skips the pause menu), quit with the task manager, load that save: `labels: a save made while hidden; the
      player's filter restored`.
   f. Close the window with labels hidden: they stay hidden; open the window: the box is ticked.
G3h. **Hide UI.** Tick "Hide UI": the whole game UI (our window included) disappears, `ui hidden (back on Esc)`.
   a. Don't touch anything for 20 s, then move the mouse over the map and pan / zoom / turn the camera: the UI
      stays hidden (no timer, no mouse or camera trigger), and the camera moves (note it if it doesn't).
   b. Press Esc: the pause menu opens and the UI is back (`ui shown (pause menu)`). **If Esc does nothing while
      the UI root is hidden, note it at once**: then the player has no way back but loading a game (PLAN.md
      "Open work").
   c. Close the menu, open the window: the "Hide UI" box is unticked.
G4. **Random place.** Subjects tab, "Random place" ten times: `jump place (random place) ...`, each somewhere
   else on the map (never off the map, never inside a hill: the camera clears the ground). "Anything" now also
   lands on random places and on the shots of S1-S12 now and then (`jump any (any place|any bridge|...)`).
G5. **Tour hides the window.** Tour tab, Start tour: the window disappears (`tour: window hidden`), the tour runs.
   Move the camera (pan, zoom or turn): the tour stops and the window is back (`tour off (camera moved: ...)`,
   `tour: window shown`). Start again and press Esc: tour off, window back. With "Hide the game UI during the
   tour" ticked: the whole UI disappears and stays hidden while the tour goes on (since round 3 no 60 s timer:
   G15); moving the camera stops it and shows the window. **Note: does camera input still work while the UI
   root is hidden?** (if not, only Esc brings it back: tell us).
G6. **Ken Burns drift and the hold timer.** Ground level, Random subjects, 10 s, "Ken Burns drift" ticked: each
   glide flows into a slow drift without a stop (no "arrive, halt, start drifting"), and the drift flows into the
   next glide without a jolt. Time a hold with a stopwatch: from the moment the camera arrives to the next
   glide's start ~10 s (log lines `tour ... to=` about 14.5 s apart). Untick "Ken Burns drift": glides end at
   rest, the camera stands still during the hold. Hover the checkbox: the tooltip explains the effect.
G7. **Tour tab layout.** The Tour tab: rows Mode / Source / Hold / Lowest view / Highest view / Closest /
   Farthest, labels in one column, the choices as separate buttons 4 px apart (selected one highlighted); the
   two checkboxes; a framed Start tour button (Stop tour while running). The Views tab: only Save view and the table ("No saved views yet." when
   empty); first row's up and last row's down greyed out. German and Japanese: rows fit or wrap inside the window.
G11. **Window width and spacing (round 3).** Open the window on each tab:
   a. The window is narrow, about 460 px wide with its frame (content 440 px; it was ~1400 px): the Subjects
      rows (11 and 12 buttons) wrap onto several lines; nothing is cut off at the right edge. Screenshot it.
   b. No two buttons touch: the same gap (4 px) between buttons in a row and between wrapped rows, in the
      Subjects / Camera rows, the saved views' row buttons and the Tour choice buttons; equal space between the
      Tour rows and its two checkboxes.
   c. Footer: padded on all sides (8 px), the three checkboxes on one line (or wrapped) with the same baseline
      and a clear gap between them.
   d. Tour tab: "Start tour" is a framed button with the accent background (not bold plain text).
   e. Game language German, then Russian: the labels and the Tour choices wrap inside the window (long Tour
      labels such as "Vue la plus basse" / "Höchste Ansicht" on two lines at most), nothing clipped; the
      window stays narrow. Status line and hints wrap.
G12. **Shadows, geometry, terrain and grass untouched (rounds 3 and 5).** Set Shadows, Geometry, Terrain and
   Grass to Low in Settings > Graphics. Tick and untick High graphics mode three times, also once ~15 min into a
   session and on the desert save of `2026-10-13_0522` / `_0558` (estimatedMb=4581, 1015 vehicles; camera looking
   almost straight down): no crash, no "Could not invert matrix", no `StaticBuffer` assert
   (`make logs-grep PAT='invert matrix|StaticBuffer|hq stage|Shadow map' ARGS='--session last'`: no `Shadow map
   change size` after the start), the four settings still Low.
G13. **Tour sources (round 3).** Tour tab, Ground level: "Sources" shows four checkboxes, Random subjects,
   Random places and Interesting shots ticked. Tick Saved views too (with 2-3 saved views), Hold 5 s, Start:
   the hops take the ticked sources in turn (`tour random ...`, `tour places place ...`, `tour view N`,
   `tour shots ...`). Untick all but Saved views: list order as before, Mixed makes no flights. Untick the last
   ticked box: it stays ticked (or ticks itself again) and the status says "Keep at least one ticked." (**note
   whether the box shows unticked while the state is ticked**). Only Interesting shots on a fresh map: the
   tour stops with "Nothing to show on this map yet." if none is found.
G14. **Aerials options (round 3).** Aerials (then Mixed): rows "Flight leg" (30 s / 1 min / 2 min / 5 min, 1
   min selected) and "Fly over" (six checkboxes, all ticked) show; Ground level hides them. Aerials, 30 s:
   after ~30 s the drone slows to rest, then glides to a new area (`tour flight new area x,y (<why>)`) and flies
   on. Untick all but Water: waypoints `(water)` over the sea / lakes; only Rivers on a map with rivers:
   `(river)` waypoints over a river (screenshot), on a map without: `flight candidates rivers=0 (none found)`
   and the drone flies on (`(ahead)`), no error. Only Rail lines: waypoints `(rail)` over tracks with trains.
   Points of interest: `(station)` / `(industry)`. Note the `flight candidates` line's counts per subject.
G15. **Tour UI stays hidden (round 3).** "Hide the game UI during the tour" ticked, Aerials, 5 min leg: start
   and wait 2+ minutes: the UI stays hidden (it came back after a minute before). Pan the camera (since round 4
   turning / tilting / zooming during a flight is mouse look, G18): tour off, UI and window back. Again, then Esc: the pause menu opens, UI back (**note if Esc does nothing while hidden**).
G16. **Horizon shots and the zoom limit (round 4).** Camera tab on a hilly map, any view:
   a. "Horizon": the camera rises to ~250 m above where the centre was and looks almost level towards the
      horizon in the same direction (`shot horizon view=x,y,d,a,p`, d ~3300, p 0.075). **Within a second, does
      the distance stay or ease back?** (read the camera again with a second Horizon click or save a view and
      compare `bookmark add ... d`): note both d values.
   b. "High horizon": `horizon clamped by zoom limit d=4000 p=0.2.. (wanted d=8000 p=0.100)`, the view ~800 m up,
      a little steeper. Same question: does 4000 m at pitch ~0.2 stay? If it eases back, note to what (then
      `cam.ZOOM_LIMIT` goes down and the finding "Camera zoom limit" gets the low-pitch limit).
   c. Describe what you see: the horizon in the upper part of the picture, sky above it? The far plane (fog)
      cutting the land off? Screenshot both.
   d. At a map edge looking outwards: the centre is clamped to the map, the view bends (expected; note how bad).
G17. **Horizon tour range (round 4).** Ground level, Highest view "Horizon", Closest 1000 m, Farthest 3500 m,
   Start: every hop `to=x,y,d,a,p` with d 1000-3500, p 0.04-0.09: high, nearly level views of each subject from
   afar. Note whether the subjects are findable at all (too far?) and whether the glides between them look good.
   The Highest view tooltip on "Horizon" explains the combination.
G18. **Mouse look while flying (round 4).** Aerials, Start: during the flight turn the camera (right mouse / Q E),
   tilt it and zoom with the wheel. a. The tour goes on (no `tour off`), the view turns / tilts / zooms with your
   input, smoothly (no fight, no jitter between your input and the flight): log `tour flight: mouse look kept as
   an offset (returns to the path)` once. b. Let go: ~0.6 s later the view drifts back to the flight's own view
   within ~5 s. c. Untick "Look returns to the path", turn: the view keeps your offset. d. Pan the camera (drag /
   WASD): `tour off (camera moved: pan)`. e. Zoom towards a point at the screen edge: not taken as a pan (the
   tour goes on); **note if a zoom stops the tour**. f. Mixed: the same during a flight leg; during a hop any
   camera input stops the tour as before. g. The Aerials mode tooltip mentions it.
G19. **Aerials look Horizon (round 4).** Aerials, Look "Horizon": the drone flies ~300 m up looking far ahead
   along its heading, nearly level (`tour on ... look=horizon`, `camera_step` max in `make perf`). Near a map
   edge the view looks inwards or shortens (never off the map). Note how it looks against Look "Down".
G20. **The way back from a hidden UI (round 4; the top risk).** a. Tick "Hide UI", wait 5 s, press **Esc**:
   does the pause menu open and the UI come back (`ui shown (pause menu)`)? **Note the answer** (the base code
   says forwarding Esc to a hidden UI root is impossible, `docs/findings/gui.md` "Input actions don't reach a
   hidden GameUIRoot"). b. If not (or after closing the menu): tick "Hide UI" again, wait 5 s, press **Space**
   (pause): the UI is back at once, `ui: pause key while hidden, bringing the UI back`, `ui shown (pause key)`;
   the game is paused now (Space's own effect; press it again to resume). c. With the game paused (speed 0)
   before hiding: Space (resume) also brings it back. d. Tour with "Hide the game UI during the tour", Aerials:
   Space: `tour off (pause key)`, window and UI back. e. Cmd+Q while hidden: the pause menu opens, `ui shown
   (pause menu)`. f. Speed 4x on a heavy save, hidden for 2 minutes: the UI never comes back by itself (the speed
   throttle changes 4x to a lower speed, never to pause). Update the finding with a-e.
G8. **Camera range.** Ground level, Lowest view Drone, Highest view Bird's eye, Closest 150 m, Farthest 900 m:
   `tour ... to=x,y,d,a,p` with d 150-900 and p 0.45-1.40. Set Lowest view Drone and Highest view Low angle (a
   "from" above the "to"): the tour still runs (the range is swapped), no error.
G9. **Modes.** Aerials: Start tour: a glide up to ~200 m, then a continuous slow drone flight (`tour flight from
   ...`, `tour flight waypoint x,y (town|station|water|country|...)` about every 1-2 minutes), gentle turns, slow
   altitude changes, never through a hill, never off the map edge; the flight starts from rest (no jerk). Run it
   5 minutes. Note the frame time (`make perf ARGS='--mod square_photo_mode'`: `camera_step` max) and whether the
   flight looks like a screensaver (speed, height, look-ahead: tune `pm_flight.FLY`). Mixed: subjects from eye
   level to drone height, a 30 s flight leg every third hop (`tour flight leg 30s`), the leg slows to rest before
   the next glide. Source is hidden for Aerials.
G10. **Look direction.** a. The first jump of a session logs `look calibrated: look heading = camera angle +X rad`;
   **note X** (expected a multiple of pi/2: 0, 1.571, 3.142 or -1.571). b. Every shot of S1-S12 faces its subject
   (a bridge seen side-on, the tunnel portal in front of the camera, the aircraft coming towards it). If they all
   face away or sideways, the calibration failed: report the log line.

### The photographer's shots (Subjects tab, "Interesting"; one check each)

For each: click it a few times on a save that has the thing; log `scan <name>: read N of M ms= ...` (note the ms:
budget 35 ms from the click) and `jump <name> (<name>) entity= kind= view=`; a map without it shows the grey
line. Note any framing that looks wrong (too close, too far, facing away, inside terrain).

S1. **Train on a bridge**: a train on a bridge, high bridges first (`height=`), seen side-on from below or level
    with the deck. None: "No train on a bridge right now.".
S2. **Crossing water**: a train or road vehicle on a bridge over a river / lake / sea, side-on, low over the water
    (`scan water: ... found=true`). Check the camera isn't under water.
S3. **Trains passing**: two moving trains within 150 m, both in frame (`scan passing: ... moving=N pair=Xm`).
S4. **Tunnel portal**: a train just before / after a tunnel, the camera outside looking into the portal.
S5. **Landing or take-off**: an aircraft in TakeOff / Landing / Approach under 400 m; the camera on the ground
    ahead of it; the aircraft flies over within a few seconds (`scan approach: ... score=`).
S6. **Busy street**: the densest road traffic (`scan rush: ... road=N best=K`), seen low along the street.
S7. **Skyline**: the biggest town from 1.1 km outside, low, across water if any (`skyline town <id> population=
    water=true|false`).
S8. **Viewpoint**: from a hill (>= 40 m above a town) looking down at the town (`viewpoint: N high points, best
    rise=`). Flat map: "No hill overlooking a town found.".
S9. **Train at a platform**: a standing, loading or departing train seen along the platform (`scan departure`).
S10. **Oldest vehicle**: the oldest model running (`scan oldest: ... year=`); repeated clicks show other old ones,
    then it again from a new angle (round 17, IV1).
S11. **Fastest vehicle**: the fastest land vehicle (`speed=..km/h`), followed (`follow on entity= (fastest)`)
    as it comes towards the camera.
S12. **Longest train**: as P5, now framed side-on.

## Rev 1 feedback round 6 (built 2026-10-13, untested; PLAN.md "Rev 1 feedback round 6")

Log lines: `make logs-grep PAT='\[PhotoMode\] (camera mode|tour|labels|place|ui)' ARGS='--session last'`. No
`ERROR` from `[PhotoMode]` after any check.

G21. **Hide labels and hover.** Footer: tick "Hide labels and hover": `labels and hover hidden (player's filter
   kept)`. a. The labels go at once (station / town names, "1/20" rates, vehicle icons). b. Move the mouse over a
   station, a train, a building: no highlight, no tooltip. c. Click a station: no window opens. d. Untick: `labels
   shown (checkbox)`, labels, highlight, tooltips and clicks back at once. e. Ticked, open a build tool (e.g.
   roads) and close it again: **note** whether the hover came back early (the selector remounted; the next tour
   start hides it again). f. Ticked, Esc: the pause menu restores both.
G22. **Layout: exact gaps (the round 3-5 spacing never applied; now class rules).** Take a screenshot of each
   tab at 100 % UI scale and measure in an image viewer:
   a. Tour tab, Ground level: 6 px between the bottom of one row and the top of the next (Mode → Sources →
      Hold → Lowest view → Highest view → Closest → Farthest → the checkboxes), the same everywhere; within a
      ToggleButtonGroup the base 4 px between buttons.
   b. Label column to its control: 6 px. Checkbox rows (Sources, Fly over, footer): 12 px from one label to the
      next box; wrapped lines 6 px apart.
   c. "Ken Burns drift", "Look returns to the path" and the three tour checkboxes: 6 px above and below each.
   d. "Start tour": 16 px above it (6 + a 4 px spacer + 6), framed accent button.
   e. Subjects / Camera / Light rows: 6 px between buttons and between wrapped lines; headings 10 px below the
      row above them.
   f. Footer: a thin line 8 px under the tab frame, the checkboxes and the "Camera mode" button 6 px under the
      line, 8 px from the window's left and bottom inner edges, 12 px between them; nothing on the window edge.
   g. Views tab: 6 px between the name, Go and the icon buttons, 6 px between rows.
   h. If none of the gaps show: a class on a FlowLayout / BoxLayout isn't matched; report with a screenshot (the
      fallback is a Component wrapper with inline padding, findings gui.md "Inline styleSheets don't apply to
      layouts").
G23. **Camera mode.**
   a. Footer "Camera mode": `camera mode: on (button)`; the UI disappears (the game's free camera); move around
      with the free camera's controls; Esc: the UI and our window come back, `camera mode: left (button
      session)`.
   b. Tour, Ground level, "Camera mode during tours" ticked (default): Start: `camera mode: on (tour)`, then
      within 2 frames either `camera mode: setCameraData drives the free camera` (the tour plays, no UI) or
      `camera mode: setCameraData ignored -> fallback hidden UI` (the free camera ends, the UI root is hidden by
      us, the tour plays). **Note which**, and whether the view really follows the tour in the first case (the
      probe compares getCameraData and getEye / getCenter; a renderer that ignores both would fool it).
   c. In camera mode during a tour: Esc → `camera mode: left with Esc / back`, `tour off (camera mode: back)`,
      window and UI back. Pan with the keyboard / mouse → `tour off (camera moved: ...)`, `camera mode: off (tour
      ended)`, everything back. **Note** whether a slight mouse move ends the tour (`camera mode: mouse detached
      from the free camera` logged at the start?).
   d. Fallback case: a second tour in the same session goes straight to the hidden UI (`game UI hidden (camera
      mode failed earlier this session)`); Space or Esc → pause menu / pause key bring everything back.
   e. Untick "Camera mode during tours": the UI root is hidden for the tour (`tour: window hidden, game UI
      hidden`), Space / Cmd+Q bring it back (G20).
   f. In camera mode, Cmd+Q: the pause menu opens, `camera mode: off (pause menu)` or `(tour ended)`, the UI back.
   g. The game bar's own free camera button still works as before afterwards (Esc returns).
G24. **This place.** Centre the view on a station in a town. Tour tab: Mode "This place": rows Area (Small /
   Medium / Large, tooltips "about 80 / 250 / 600 m"), Hold, Lowest view, Highest view, Ken Burns drift; no
   Sources, Closest or Farthest. Start (Medium): `place subjects r=250 buildings=N vehicles=M (read R of T)
   persons=K ms=X` (X below ~40), `tour place x,y r=250 subjects=...`, then hops `tour place point to=...` and
   `tour place building|train|road|person entity=... to=...`. a. Every shot stays around the place, from all
   sides (8 directions per round, in a shuffled order), from eye level to drone height; about half aim at a
   nearby vehicle, person or building. b. It never leaves the area. c. After ~6 hops the subjects are looked up
   again (a new `place subjects` line). d. Small / Large: tighter / wider. e. An empty spot of the map: only
   place points (subjects=0), no error.
G25. **Hide labels during tours.** Default ticked: start any tour: `tour: window hidden, ... labels hidden`; the
   labels and hover are gone during the tour, back after it (`labels shown (tour ended)`). With "Hide labels and
   hover" already ticked before the tour: they stay hidden after it. Unticked: the labels stay during the tour.
G26. **Pause the game during the tour.** Tick it, start a tour: `light freeze on (speed was N)`; trains stand
   still; stop the tour: `light freeze off (tour ended): speed N back`. With "Freeze time" ticked on the Light
   tab before the tour: nothing changes afterwards (still frozen). Space during a hidden-UI tour: the tour stops
   (G20) and the game runs.
G27. **Tour performance.** Aerials 5 min legs, then This place, 5 minutes each, `sqperf_log` On: `make perf
   ARGS='--mod square_photo_mode'`: `camera_step` max well below 16 ms; `tour_advance`, `tour_flight_start`,
   `place_subjects` once per hop / leg, no slow lines; `flight candidates ...` once per leg (not about once a
   minute as before). Compare the frame time with labels hidden vs shown during a tour (G25).
G28. **Languages.** German, Russian and Japanese: the Tour tab in each mode and the footer wrap inside the window,
   nothing clipped (the German "Beschriftungen bei Rundflügen ausblenden" is the longest checkbox).

## Rev 1 feedback round 7 (built 2026-10-13, untested; PLAN.md "Rev 1 feedback round 7")

Log lines: `make logs-grep PAT='\[PhotoMode\] (eye check|tour|wander|camera mode|shot)' ARGS='--session last'`.
No `ERROR` from `[PhotoMode]` after any check. A hilly map (or a hilly part of one) shows R1-R3 best.

R1. **The eye no longer follows the terrain (the main fix).** Tour, Ground level, Ken Burns on, Hold 10 s,
   sources Random places + Interesting shots, over hilly land. a. Watch the glides between places and the holds:
   the camera moves like a smooth dolly / crane; no bobbing up and down as the look-at point slides over bumps
   (before: "it follows the terrain map"). b. The log: `eye check (hop arrived): planned x,y,z engine x,y,z
   dz=... lift=... height reads=N/frame` for the first 3 hops. **Report dz**: near 0 (within ~1 m) confirms that
   the game puts the camera centre on `getHeightAt`'s ground (the model the fix relies on). A constant or
   growing dz, or a large one over water / on bridges: report the lines (the model is off there). c. `height
   reads` 3-4 (up to 7 in a rare frame). d. Low eye-level shots on a slope don't dip into the ground.
R2. **Aerials over hills.** Aerials, Look Down, then Look Horizon, 2 min each over hilly land. The drone climbs
   before a hill and sinks slowly after it, no bobbing; the look moves smoothly. `eye check (flight)` once per leg
   (dz near 0). Mouse look (turn / tilt / zoom) still works as an offset; a pan still stops the tour.
R3. **Ken Burns: pace and moves.** Ground level, Ken Burns on, Hold 20 s, 10 hops. Each `tour ... to=...` line
   ends with `kb=<move> x<pace>`: a. the moves vary (push, truck, pedestal, orbit, tilt; orbit and tilt the rarer
   ones), the pace between x1.0 and x2.5. b. On screen: push = moving in or out, truck = sliding sideways,
   pedestal = the camera rising or sinking (with a little tilt), each smooth, the glide flowing into it without a
   jolt and the 20 s counted from the arrival. c. Is the slowest (x1.0) still pleasant and x2.5 not too fast?
   **Report** a preferred range.
R4. **Bird's eye and the keys (was: "WASD inverted").** Camera tab, Bird's eye: `shot bird view=...,1.300`.
   Press W, A, S, D: W moves the view up the screen (as in a normal view), A left. a. **Report** whether the keys
   are right now. b. If still inverted: tilt the camera with the mouse as steep as the game allows, click Save
   view in the Views tab and report the `bookmark add ... ,<pitch>` value (the game's own steepest tilt), so the
   cap (`cam.PITCH_MAX`, 1.30 since round 8) can be set from it.
R5. **Wander (camera move).** Centre a busy station, Camera tab "Wander": `wander on (camera move) x,y r=R pitch
   a-b subjects=N`; the camera eases from where it is into a slow, endless drift around the place: in and out,
   around, up and down, never through the middle, the look moving between nearby buildings, vehicles and people
   (`wander look at <kind> x,y` every ~10 s). a. No cuts, no jumps, no bobbing over hills. b. Zoom or turn the
   camera: `wander off (camera moved: ...)`. c. Orbit while wandering: the wander stops, the orbit starts (and
   the other way round). d. Close the window: `wander off (...)`.
R6. **Camera mode: does setCameraData drive the free camera? (settles the finding)** Tour tab: tick "Try
   camera mode during tours" (off by default now), Ground level, Start. a. The log shows `camera mode: on
   (tour)`, then (once the first glide has moved the view) up to two lines `camera mode: probe frame N (waited
   W) set=... read=... eye=... centre=... |eye-centre|=... match=...` and the verdict. b. **Report the lines**
   and what the screen did: if `eye=` stays put while `set=` moves, the free camera is its own camera
   (expected: `setCameraData ignored -> fallback hidden UI`, and the tour goes on with the UI hidden). c. If it
   says `drives the free camera`, check the view really follows the tour.
R7. **Tooltips everywhere.** Hover every control of every tab and every Tour mode (Mode options, Area, Hold,
   Angle from / to options, Distance from / to options, Flight leg, Look, every checkbox, the Light tab's step
   buttons and presets, the Views tab's row buttons, the footer): each shows a tooltip; the row labels (Mode,
   Area, Hold, Angle from, ...) show one too. **Report** any control without one.
R8. **Angle and distance rows.** Tour tab, Ground level: the rows read "Angle from", "Angle to", "Distance
   from", "Distance to"; their tooltips explain angle (how steeply the camera looks down) vs distance (how far
   away). Angle to "Bird's eye" is now 1.30 (no WASD trouble in tours either, R4).
R9. **Wander tour.** Mode "Wander" (rows: Area, Angle from, Angle to; no Hold, no Ken Burns): Start over a town
   (Medium): `wander on (tour) ... r=250`, `tour on mode=wander ...`; the window hides as for any tour; the
   camera drifts around the place for 3+ minutes without cuts, height and angle varying within the angle rows.
   Esc / the pause key / a pan stop it (`tour off (...)`; the wander ends with the tour). Area
   Large: wider, a little faster over the ground.
R10. **Performance.** `sqperf_log` On, R1 and R9 for 3 minutes each: `make perf ARGS='--mod square_photo_mode'`:
   `camera_step` max still well below 16 ms (the solver adds 3-7 `getHeightAt` a frame); `place_subjects` once
   per wander start.

## Rev 1 feedback round 8 (built 2026-10-13, untested; PLAN.md "Rev 1 feedback round 8")

Log lines: `make logs-grep PAT='\[PhotoMode\] (pitch offset|cam trace|eye check|tour|wander)' ARGS='--session
last'`. No `ERROR` from `[PhotoMode]` after any check. A screenshot of each tab answers U1-U5 at once.

U1. **Option sets: outlined cells.** Subjects tab: "Random subject" and "Interesting" are grids of equal cells,
   three per row, each with a thin accent outline (the game's own outlined button) and little padding: rows
   close together, no tall borderless blocks. A long label ("Landing or take-off", and in German / Russian)
   wraps inside its cell; the cells stay the same width. Hover: the outline brightens; click: the jump works.
   **Report** a screenshot; three per row, or two (then the cell is a few px too wide for the row)?
U2. **Camera tab.** Shot buttons the same cells; Orbit / Wander / Follow / Cockpit the same size, filled (the
   base toggle look), the one that is on highlighted. Light tab: the seven presets as cells; the step buttons
   (`<<`, `<`, `>`, `>>`) outlined and compact. Views tab: Save view, Go and the row icons outlined and compact.
U3. **Tour tab: the Mode dropdown.** Mode is one dropdown (Ground level, Aerials, Mixed, This place, Wander):
   a. it opens over the window and closes on a pick; the rows below change with the mode (as before). b.
   Hovering an item in the open list shows its tooltip; the closed box's tooltip describes the selected mode. c.
   The other choice rows (Hold, Angle, Distance, Flight leg, Look, Area) are compact option buttons (smaller
   than before). Start tour is still the filled accent button. **Report** if the dropdown misbehaves (does not
   open, closes the window, crashes): the fallback is the option row of round 7.
U4. **Footer padding (the real fix).** On every tab: the footer's checkboxes start at the same x as the tab
   content's text (about 20 px from the window edge), the separator above them too; space below the footer
   to the window's bottom edge; nothing touches the edges. "Camera mode" is an outlined button: on the
   checkboxes' line if it fits (likely not in English at 440 px: then on the next line, left-aligned). The
   status line (after a jump with nothing found) sits in the footer under the controls, inset the same.
U5. **The tab content.** The whole window has 8 px around the tabs; the tab frame doesn't touch the window edge.
U6. **Saved views in the pool.** Save 2-3 views (Views tab). a. Subjects tab "Anything", 15 clicks: now and
   then `jump any (any saved) ... kind=saved view=...` and the camera goes exactly to one of your views. b. Tour,
   Ground level, sources only "Interesting shots", 12 hops: about one hop in ten is `tour shots saved (saved view
   N) ...` to exactly that view (with a gentle Ken Burns drift, half the usual). c. With no saved views, nothing
   changes (the saved kind is skipped).
U7. **Tooltips.** Anything, Save view and the "Interesting shots" source mention the saved views. R7's audit:
   every control (dropdown items included) has a tooltip.
U8. **The height bumps (the main fix).** Tour, Ground level, Ken Burns on, sources Random places + Interesting
   shots, over hilly land; then a Wander tour; then Aerials 2 min. a. The first move logs `pitch offset
   measured: eye-centre elevation = camera pitch +0.xxx rad (d=, p=)`: **report the value** (expected ~0.22-0.34
   from the last session's eye checks). b. `eye check (...)` lines: `dz=` now near 0 (within a few m); report
   them with their `set=` / `centre=` / `g=` / `off=` fields. c. On screen: no height bumps in glides, drifts
   or the wander; the low eye-level shots are lower than before (the eye now goes where planned; before it sat
   ~0.25 rad steeper). d. If dz is still large: the trace (U9) tells why.
U9. **The per-frame trace (confirms the model).** Logged by itself for the first 40 frames of the session's
   first two moves (every move with "Debug: performance log" On): `cam trace f=N read=x,y,d,a,p eye=x,y,z
   centre=x,y,z hat=H plan=x,y,z set=x,y,d,a,p g=G sample=S off=O scr=sx,sy`. Nothing to watch: after U8,
   `make logs-grep PAT='cam trace' ARGS='--session last'` and hand over the lines. They show a. whether `eye`
   equals `plan` (the compensation works), b. whether `centre` z equals `g` (the game's centre on getHeightAt's
   ground), c. whether `sample` is constant or changes with the distance / pitch (`read=`), d. `scr=`: where the
   game's centre shows on the screen (0.5,0.5 = the middle: the screen middle looks at the centre; lower, e.g.
   0.5,0.7: the screen middle looks along the pitch), e. `hat` = getHeightAboveTerrain.
U10. **Bird's eye and the keys.** Camera tab, Bird's eye (1.30, unchanged); WASD pan the right way (R4).
   Mouse-look during a flight can't tilt past 1.30 any more (`cam.PITCH_MAX` 1.35 -> 1.30: with the offset,
   1.35 + ~0.23 is about straight down).
U11. **Performance.** `sqperf_log` On, U8 for 3 minutes: `camera_step` max still well below 16 ms (round 8 adds
   getEye + getCenter a frame of a move; the trace lines only in the first 40 frames).
U12. **Regression.** Orbit, jumps, shots and saved views' Go look as before (they send the game's pitch
   directly, no compensation); Follow and Cockpit unchanged.

## Rev 1 feedback round 9 (built 2026-10-13, untested; PLAN.md "Rev 1 feedback round 9")

Log lines: `make logs-grep PAT='\[PhotoMode\] (hover|camera model|cam trace|eye check|eye smoothness|tour|wander)'
ARGS='--session last'`. No `ERROR` from `[PhotoMode]` after any check. Hilly land shows V2-V6 best. Leave "Hide
labels and hover" (footer) unticked for V1a-c.

V1. **No hover during automated moves (the user's first point).** a. Tour tab, any mode, Start: `hover off
   (automated camera move)`. Move the mouse over stations, trains, buildings while it runs: no highlight, no
   tooltip; click one: nothing opens (the click may stop the tour as camera input; nothing gets selected). b.
   Stop it (pan, Esc, the pause key Space): `hover back (camera move ended)`, the highlight and tooltips work
   again at once. c. Camera tab: Wander, then Orbit (replacing it): no hover during either, one `hover off` line
   only (no off / on in between); click Orbit again: `hover back`. d. Tick "Hide labels and hover", run a tour and
   stop it: no `hover back` line, the hover stays off until you untick it. e. **Report** if the hover still shows
   during a tour in any mode (the selector is prevented at the start and again 2 and 30 frames later; if it comes
   back later, say after how long or after what).
V2. **Camera model, glides (the main fix).** Tour, Ground level, Ken Burns on, Random places + Interesting shots,
   3 minutes over hilly land. a. Watch: glides and holds without small jumps or wobbles of the camera height. b.
   `camera model: first sample offset +0.xxx rad, model +0.xxx, residual +0.0xx (d= p=)`: **report** it (the
   residual expected within about +-0.02). c. `eye check (hop arrived)` lines: `dz=` now within about 1 m (round
   8: +3.4 to +4.6, the centre's 4 m lift), `centre=` z = `g=` + 4, `model=` close to what the line's eye / centre
   show, `res=` small.
V3. **Wander (camera move and tour).** Camera tab Wander over a hilly town, 2 minutes; then Tour mode Wander
   (Ground level angle rows), 3 minutes. a. **Report**: does it still feel jerky? b. The look stays on the
   buildings / vehicles (an eye-level angle range now raises the eye where the game can't look that flat from far
   away: expected, the game's camera can't). c. The trace: 45 `cam trace` lines in the first 10 s of each wander
   (40 + a burst of 5 at frame 600), 5 more at 30 s and 60 s; none shows `eye=-,-,-`.
V4. **Eye checks with water and long distances.** Mixed tour with Random places near the coast / lakes, and an
   Aerials leg: `eye check` lines over water show `centre=` z = 4.0 (water level 0 + 4: **report** if not), and at
   distances above 400 m (flights) `model=` vs the eye / centre in the line (the model is extrapolated there).
V5. **The smoothness numbers (settles V2-V3 objectively).** After V2 and V3: `make logs-grep PAT='eye
   smoothness' ARGS='--session last'`. One line per hop, flight leg, 30 s of wander, and a `... total` per move.
   **Report** the lines. Smooth: `jerk max` a few m/s2 per frame at most during holds and wanders (a glide's ease
   gives steady `acc`, not jerk spikes); `d2 max` a few cm in holds and wanders. A large `jerk max` names its frame
   (`worst f=`): compare with the `cam trace` frame of the same move when traced.
V6. **Low and steep looks.** Camera tab: an eye-level shot, then Wander from there; and Bird's eye, then Wander
   from there. Both start without a jump (the glide-in begins at the current view) and stay smooth.
V7. **"Try camera mode during tours" is gone.** Tour tab: no such checkbox; "Hide labels during tours" says it hides
   the labels (no hover mention: the hover is always off now). The footer's Camera mode button still works (the
   game's free camera, Esc returns: `camera mode: on (button)` / `left (button session)`).
V8. **Bird's eye and the keys.** Camera tab Bird's eye (still 1.30): W pans up the screen, A left (R4). The new
   camera model says 1.45 never looked past straight down, so the round 7 inversion is unexplained: **report** if
   1.30 is fine; if the keys are inverted, save a view at the steepest mouse tilt and report its pitch (R4b).
V9. **Performance.** "Debug: performance log" On, V2 and V3 for 3 minutes each: `make perf ARGS='--mod
   square_photo_mode'`: `camera_step` max well below 16 ms (eye checks show `height reads=3-5/frame`; up to 14 in
   a rare frame).
V10. **Regression.** Orbit, jumps, shots, saved views' Go, Follow and Cockpit as before; the This place and
   Aerials tours run and stop on a pan / Esc / Space with the UI and window back (no camera mode push any more).

## Rev 1 feedback round 10 (built 2026-10-13, untested; PLAN.md "Rev 1 feedback round 10")

Log lines: `make logs-grep PAT='\[PhotoMode\] (view tool|hover|smooth|camera model|eye smoothness|tour)'
ARGS='--session last'`. No `ERROR` from `[PhotoMode]`. Hilly land for W3-W5.

W1. **No hover, tooltips or money floaters during automated moves (our view tool).** a. Tour tab, Aerials, Start:
   `hover off (automated camera move)` then `view tool on (automated camera move): no hover ...`. Move the mouse over
   buildings, stations, trains: no white outline, no tooltip; no "$" income / cost floaters anywhere. b. Esc: `view
   tool off (pause menu)` (or `(camera move ended)`), hover and floaters back. c. **Report**: with "Hide labels during
   tours" unticked, do the town / station labels still show during the tour? (Whether our tool on top also hides the
   default selector's HUD icons is inferred.) d. Camera tab: Wander, then Orbit replacing it: one `view tool on`, no
   off / on between. e. Footer "Hide labels and hover" ticked, no move running: `view tool on (labels hidden)`; hover
   and click-to-select off on the map, labels gone; untick: `view tool off (labels shown)`, everything back. f. While
   a Wander runs, open a build menu from the game bar: `view tool: removed by another tool ...`, the build tool works
   (stop the wander by moving the camera). g. **Report** any hover seen while a `view tool on` line is the latest.
W2. **Aerials smoothness (the refit).** Tour, Aerials, Look down, 3 legs over hilly land. a. **Report**: still jerky?
   b. `camera model: first sample offset ... model ... residual` (once a session): the residual within about +-0.01
   now (was -0.114 at 810 m). c. `eye smoothness (flight)` lines: `d2 max` below about 1 m in the legs (was 5.9-25.7),
   `cuts=0` (a cut in a flight would be a bug: report), `guarded=` small. d. `eye check (flight)` lines: `dz=` within
   about 1 m (was -1.4 to -2.5). e. **Report** the lines and the worst `f=` of any line with `d2 max` above 2 m.
W3. **Large Wander.** Camera tab Wander zoomed out to about 800-1000 m over hills (as the session's r=800): `eye
   smoothness (wander)` `d2 max` below about 1 m (was 14.8 / 5.5), and it looks smooth. Then a Wander tour zoomed out
   to ~1700 m first (the glide in passes 1500 -> 800 m where the game lowers its centre): no drop or jump while it
   comes in (`cam trace` centre z rises from the water level to the ground + 4 as d falls from 1500 to 800).
W4. **Smooth camera.** Footer "Smooth camera": `smooth camera on strength=medium level=false`, `view tool on (smooth
   camera)`, `smooth camera: window and game UI hidden`. a. Move with WASD / arrow keys, edge scroll, drag, rotate,
   tilt and the wheel: the view glides after the keys and stops softly; the wheel zooms like the game's (no extra
   lag, no overshoot), towards the cursor. No hover outline or tooltip. b. **Report** whether anything fights (a
   wobble after letting go, a drift, overshoot) and which control. c. `make logs-grep PAT='smooth trace'`: after a key
   is let go, do the `step=` values go on for a few frames (the game easing pan / turn itself)? **Report** them: then
   that channel should pass through like the zoom. d. Esc: the pause menu opens, `smooth camera off (pause menu)`,
   window and UI back. Again, then the pause key (Space): back too. e. Camera tab: Smoothing Low / High (Low: close,
   High: long glides), each switch logged `smooth camera strength ...`.
W5. **Level zoom.** Camera tab tick "Level zoom", then Smooth camera, at about 200 m looking at 30°: zoom out with the
   wheel to 1-2 km: the view keeps looking at the land at the same angle (the camera backs away along the look)
   instead of tilting towards straight down; zoom back in. Tilt still works. Untick while running: no jump.
W6. **Bird's eye.** Camera tab Bird's eye: the view is about 86° down (sent ~1.25 at 900 m); W pans up the screen,
   A left (R4 / V8). **Report** if inverted.
W7. **Free camera** (the old Camera mode): the footer's "Free camera" button: the game's free camera, Esc returns
   (`camera mode: on (button)` / `left (button session)`), tooltips in German / Japanese fit.
W8. **Layout and languages.** Footer: two buttons after the checkboxes, wrapping; the Camera tab's Smooth camera
   section (heading, Smoothing row, Level zoom, the note) in English, German and Japanese.
W9. **Regression.** V2 (ground tour glides), V3 (Wander at 60-130 m: `d2 max` a few cm as the session's last Wander,
   0.08-0.35 m), V10 (moves stop on a pan / Esc / Space with the UI back).

## Round 11 camera fixes (built 2026-10-14, untested; PLAN.md "Round 11 camera fixes")

Log lines: `make logs-grep PAT='\[PhotoMode\] (view tool|back|smooth|screenshot|tour flight|eye smoothness)|Selected
entity|Screenshot: wrote' ARGS='--session last'`. No `ERROR` from `[PhotoMode]`; no `view tool: no HUD icon config`.

Z1. **No hover with our tool's own action.** a. Footer "Hide labels and hover", no move: `view tool on (labels
   hidden): ... action set` (or `pending`). Move the mouse over buildings, stations, trains: no white outline, no
   tooltip; left-click a building: nothing opens and no `Selected entity` line follows. b. Smooth camera: the same
   (`view tool on (smooth camera)`), clicks select nothing. c. A tour (Aerials): the same. d. Untick / Esc: hover
   and click-to-select back (`view tool off ...`). e. **Report** any `Selected entity` while a `view tool on` line is
   the latest, and whether the outline showed. If it still shows: reword "Hide labels and hover" (PLAN.md item 3).
Z2. **Right click ends the smooth camera.** Game settings, Mouse: "Back With Right-Click" on (default). a. Smooth
   camera, a short right click on the map: `smooth camera off (right click) ...`, window and UI back. b. Again, then hold the right button and drag (if that turns the camera in your controls):
   **Report** whether the drag also ended it (then a turn by right drag can't be used in the smooth camera). c. A
   tour and a Wander: a right click ends them (`tour off (right click)`). d. Labels hidden, nothing running: a right
   click logs `back (right click): nothing to end` and changes nothing. e. With "Back With Right-Click" off: Esc
   still works. f. Tooltip and the Camera tab note read "Esc or a right click brings ... back" (en, de, ja).
Z3. **Labels with our tool on.** a. "Hide labels during tours" unticked, footer "Hide labels" unticked: during a tour
   the town / station / vehicle labels and the money floaters show as the HUD filter says (they did not need to go
   with the hover). b. Tick "Hide labels", then start the smooth camera: no labels or floaters; Esc, untick: the
   labels come back. **Report** if labels vanish whenever our tool is on, or never
   come back.
Z4. **Smooth camera start (not fixed: cause found).** Smooth camera, press and hold a direction key: the first frame
   still jumps by one frame of the game's normal speed, then the view glides (PLAN.md item 1). **Report** if it
   looks different from round 10, and whether you want the keyboard-speed trial (the game's own key speed lowered
   while the smooth camera runs).
Z5. **Screenshots say they freeze the game.** Window open. a. 4x: the status "Saving the 4x screenshot: the game
   freezes for 10 seconds or more." shows BEFORE the freeze; after it: "The screenshot is in the game's screenshots
   folder."; log `screenshot scale=4 announced ...`, then the game's `Screenshot: wrote`, then `screenshot scale=4
   ... call ms=N`: **report** N (the session's: ~11000). b. 2x: "... for a few seconds", `call ms` ~3000. c. 1x: no
   announcement, at once. d. The 2x / 4x tooltips say "freezes" (en, de, ja fit). e. First shot of a fresh game at
   4x: the announcement shows from the primer on.
Z6. **Aerials without a slow-down.** Tour, Aerials, Leg 30 s, Start from a still view. a. The glide up lands on the
   moving drone: no stop, then start; the speed builds during the glide and goes on. b. At each leg's end the camera
   leaves the drone still flying, jumps to the new area and lands on the next drone already at speed (log `tour
   flight leg 30s at cruise from ...`, `tour flight new area ...`). **Report** any slow-down, a turn back, or a jolt
   at either end of a jump. c. `eye smoothness (flight)` and `(tour total)` lines: `cuts=0`; **report** `acc max` /
   `jerk max` vs the session's (8670.7 / 15619.8 for the whole tour).
Z7. **Mixed after a flight leg.** Tour mode Mixed: after a flight leg the hop to the next subject leaves the drone
   flying (no stop before it), arrives as before. **Report** anything odd.
Z8. **Regression.** W4 (smooth camera controls, Esc / pause key), W1f (a build menu during a Wander: `view tool:
   removed by another tool`), X3 (2x / 4x files and sizes), V10 (moves stop on a pan / Esc / Space).

## Round 21: Aerials High with the DEV mod, unattached flight anchors, no button style setting (built 2026-10-14, untested; PLAN.md "Round 21")

- [ ] R21-1: DEV mod on, Tour tab Aerials, Look High, Start tour: the scripted flight runs ~1 km up (log
  `cutscene fly skipped: the High look flies the scripted flight`, then `tour on mode=aerial ... look=high`).
- [ ] R21-2: DEV mod on, Look Down or Horizon: the cutscene flight still plays (250 m up). When one logs
  `cutscene fly NOT attached ... anchor N left out of later flights`, Esc and Start again: the next flight never
  uses anchor N (session `2026-10-14_2332_r20-test` repeated the same unattached anchor five times).
- [ ] R21-3: Without the DEV mod, Aerials High: visibly high from the first seconds, never framing past the map
  edge.
- [ ] R21-4: The mod's settings show only "Debug: performance log"; the top-bar button is the camera icon.

## Round 20: Animals tab, a jump follows, the speed after a cutscene, telephoto within 1.5 km (built 2026-10-14, untested; PLAN.md "Round 20")

Results of round 19 (`2026-10-14_2150_r19-test`, log and user): 28 lens plays, 1 refusal (an object 290 % off);
1 "framed wider", 2 NEAREST OBJECT; R19-2 only three orbits, all 50 mm (no 400 mm orbit tried); R19-3 Steady not
tried; R19-4 152 animals spawned (gulls, eagles) with no limit, every cougar click refused ("noise 60"); R19-5 the
arrow dent is gone (user); HQ1 passed (6 `hq stage i/6` lines twice, no crash). R18-3: the bar wrapped at load,
never used. The user: the game paused after cutscenes, telephoto looks weird, the subject orbit too fast.
Log lines: `make logs-grep PAT='\[PhotoMode\] (animals [a-z_]+ \(|lens (end|hold|orbit)|cutscene .*end|.*speed went)' ARGS='--session last'`.

R20-6. **The game keeps running after a lens view (run first).** Game running at normal speed. Lens view (World
   "Your speed"), press Esc after 2-3 s; repeat 5 times, also with Orbit. Expect the game still running each time.
   Log: `lens end: ... game speed 1 kept` and, when the game paused itself, `lens end: the game speed went to 0
   N ms after the end; the player's 1 back` (**report** N: how late the pause comes). Then pause the game
   yourself (Space), Lens view, Esc: it stays paused.
R20-1. **Animals tab: they show.** The paw tab (second). From a low view (eye level) and a high one (drone): add
   Herd of deer / Lone horse / Flock of gulls with Distance Close, Middle, Far. Expect them in the frame each
   time, bigger with Close, near the middle and lower part of the screen; gulls up in the air in the frame. The log
   `animals <group> (...): N of M placed, <dist>, <form>, facing ...; middle x,y on screen u,v, P % of the screen
   high (asked Q %), D m from the eye`. From very high up: "Added, but far from the camera ...". Looking at the sky
   only: "No ground in the view ...".
R20-2. **Formations and facing.** Herd of horses with Line across, Single file, Spread out; Facing To the camera,
   Side-on, Away. Expect a row across the view, a file going away from the camera, animals spread over the width;
   the facing visible for the first seconds (then they move on).
R20-3. **Never refused; the dying note.** Desert map: Lone cougar on flat ground (round 19: always "no place").
   Expect it added; if the spot doesn't suit it the status says "they may die within seconds" (log `score there
   <0`; then `life cougar ... GONE after N s`). Another climate's animal (deer in the desert): added with "They
   don't live in this map's climate". The tab's last line explains the dying. "Remove all" (renamed) still
   removes ours only.
R20-4. **Horses live anywhere.** Lone horse / Herd of horses on any ground near a road or in town. Expect them to
   stay (log: no `GONE` within 3 minutes; `alive after 180 s`). **Report** if they die or never appear (`spawn
   horse ... ok=false`): the draft horse model is spawned by no base game code.
R20-5. **A jump follows.** Subjects: Vehicle, Train, Person. Expect the camera to follow the subject at once (the
   Follow toggle on; its tooltip says so); a click on Follow stops it. Interesting shots (Train on a bridge,
   Tunnel portal, Landing or take-off) stay still and wait for their subject.
R20-7. **Slower subject orbit (DEV mod).** Jump to a bus, Orbit. Expect one turn in about 48 s (round 19: 24 s);
   log `cutscene orbit ... 48 s: playing` and the pace line around 16 m/s for a standing subject.
R20-8. **Telephoto within 1.5 km.** Telephoto and Super telephoto Lens views from a drone-height view, with and
   without a look (Golden glow, Dust storm). Expect the log's `D` at most 1500 m (`tighter to stay within 1500 m`),
   a tighter frame than your view, less wash-out than round 19's 3.6 km shots. **Report** if it still looks wrong
   (what: haze, coarse models, flicker).
R20-9. **Tabs and texts.** Eight tab icons in one row (16 px now; the paw second), none cut off or scrolling;
   Settings tab: High graphics mode and Hide labels, then the shadows note, no DEV rows; Views tab: the
   description under "Saved views".

## Round 19: lens sizes and fallback, Vehicle Steady, animals without a limit, compact arrows (built 2026-10-14, untested; PLAN.md "Round 19")

Results of round 18 (`2026-10-14_2019_r18-test`, user): R18-5 the vehicle stays centred but is jerky over small
hills and sharp turns (no easing exists: R19-3); R18-6 the lens refused 24 of 35 tries (R19-1, R19-2); R18-2 better,
still a small notch on the left (R19-5). R18-3 (the bar) and R18-7 not reported yet; R18-1 next.
Log lines: `make logs-grep PAT='\[PhotoMode\] (lens|animals (remove|not))' ARGS='--session last'`.

R19-1. **The lens on ordinary landscape.** Put the middle of the view on fields, hills or a road with nothing on
   it; try every lens, Hold, 5+ places. Expect almost every try to play. The log's `lens hold ...` line ends its
   anchor part with `+N size` (0: your framing; negative tighter; positive wider) and `NEAREST OBJECT` when no
   object was near the middle; the status line says "Framed tighter ...", "Framed wider ..." or "No object at the
   middle of your view: the lens looks at the nearest one". **Report** a shot that frames something you did not
   expect, and any remaining `not started` line.
R19-2. **400 mm orbit and holds near the map's edge.** Super telephoto, Orbit, at 3-5 places (the middle of the
   map and near an edge). Expect it to play, "Framed tighter so the lens camera stays on the map", the log's
   `size bucket -N: framed tighter` with D 1333-2667 m. **Report** an orbit that ends by itself within a second
   (the `lens end ... after 0.x s` line).
R19-3. **Vehicle: Steady.** Follow a bus or train, Camera tab: Vehicle "Steady", Lens view (Telephoto). Expect a
   still camera beside the road / track, the vehicle driving through the frame (not followed). "Ride along" is
   the round 18 behaviour (centred, every bump shows). Does Steady suit the shot better?
R19-4. **Animals without a limit.** Subjects tab: add Flock of gulls 5+ times (past 64). Expect no "That's enough
   animals" message; under the buttons "Added here: N animals ..." and one row per species with "Remove N". Remove
   one species: only those go (`animals remove gull: N sent ...`), the other row stays. No frame drops from the
   life checks with 100+ animals.
R19-5. **Arrow buttons.** Light tab sliders and Weather look rows: the arrow buttons draw the game's small-button
   outline (the text field's, smaller corners); **report** any notch left, and whether hover / pressed still
   colour them like the other buttons.

## Round 18: risky graphics (DEV), arrow buttons, the cutscene bar, lens locks and coverage, Hide labels (built 2026-10-14, untested; PLAN.md "Round 18")

Log lines: `make logs-grep PAT='\[PhotoMode\] (lens|bar|DEV risky|stop button)' ARGS='--session last'`.

R18-3. **The cutscene bar and F9 (run first).** Camera tab, Lens view (any lens). While it plays, top right of the
   screen: a dark bar with a camera icon, 1x, 2x, 4x and Stop. Expect: the bar shows only while the lens plays
   (and during a lens tour); hovering shows tooltips; 1x saves a screenshot (log `bar: screenshot 1x pressed during
   the cutscene: ...`, then the game's `Screenshot: wrote ...`); the picture has no bar in it. Stop ends the view
   (`lens stop button: stop file played`, then `lens end: ...`). Then press **F9** during a lens view: a 2x
   screenshot (the game's own key; verified to work during a DEV flight in `2026-10-14_1729`). At load the log
   has `[PhotoMode] bar: FreeCamOptions wrapped ok`. **Report**: no bar at all (the wrapper did not apply), a bar
   that ignores clicks (the cutscene takes the mouse: then F9 is the way), or the mouse cursor hidden. Also check
   the game bar's free camera still works and Esc leaves it (the wrapped recipe is its exit).
R18-5. **Super telephoto on a vehicle on a hill.** Jump to a bus or train on a hilly route; Lens Super telephoto,
   Hold, World "Normal"; watch for 20-40 s. Expect: the vehicle stays in the middle the whole time; on a grade the
   whole view tilts with it (the background slides up or down), but the camera no longer swings away from the
   vehicle or points at the ground. Log: `lens check ... aim on screen +0.0x,+0.0y: looking at it`. A 400 mm shot
   of a plane taking off the same way. **Report** a camera that still loses the vehicle (with the time).
R18-6. **How often the lens starts.** Put the middle of the view on ordinary scenery (a town street, a field edge,
   a station) and try Telephoto and Super telephoto 5-10 times at different places. Expect most to play (the
   1729 session refused 17 of 29). Log: `lens hold ...: ... the centre P % of the frame off its middle, buckets +h
   heading +e elevation (...)`: P up to 20; refusals now say `the best of N candidates ... (over 20 %)` or `none
   frames the centre`, and the status line "No object close enough to the middle of the view for this lens ...".
   A leaning model is skipped (`N leaning static anchors skipped`).
R18-2. **Arrow buttons.** Light tab sliders and Weather tab look rows: the step buttons show the game's filled
   arrow icons in an outlined button with no notch in the sides; hover / pressed states as the other buttons.
R18-7. **Hide labels.** Settings tab: the checkbox reads "Hide labels" (in your language), its tooltip says the
   outline under the mouse may still show. Behaviour as before (labels, tooltip and clicks off). Tours, Wander,
   Orbit and the Lens still turn hover and clicks off while they run.
R18-1. **(Done 2026-10-14, `2026-10-14_2019_r18-test-risky`: grass / terrain / geometry passed, shadows crashed;
   the DEV rows were removed in round 20.) DEV: risky graphics (expect a possible crash; DEV mod on).** Settings tab, at the bottom: "DEV: risky
   graphics" with Shadows / Geometry / Terrain / Grass: high. Set your own Settings > Graphics for those four
   below High first. Tick one box at a time, wait 10 s, untick, then the next. Each tick logs `DEV risky marker
   written ..., saved` (the first) and `DEV risky <key>: setting a -> 2 ALONE (checkbox) ...` then `... done ms=`;
   untick logs the way back. On a crash the log ends on the key's "setting" line: **report** it with the session
   name. After a crash, the next load logs `DEV risky start: a marker ... putting back <keys>` and Settings >
   Graphics shows your own values again. Esc with boxes ticked: every key back (`(pause menu)` lines).

## Round 17: lens aim, world speed, lens tour; animal groups; Orbit's target (built 2026-10-14, untested; PLAN.md "Round 17: lens, animals, orbit")

No DEV mod needed except OR3. Log lines:
`make logs-grep PAT='\[PhotoMode\] (lens|animals|orbit|cutscene orbit)' ARGS='--session last'`.

LA1. **Lens on any map (the quick path).** Subjects tab: jump to a Vehicle (or Station / Town); Camera tab: Lens
   Telephoto, Move Hold, World "Your speed", "Lens view" (one line in your language). Expect the UI to hide and the
   subject to stay in the middle. Log: `lens hold sqpm_lens_t_<s>_<e>_<h>: anchor N (<how> D m from the centre, yaw
   Y; the centre P % of the frame off its middle (...)) ...; heading h = A deg in the anchor's frame (anchor yaw
   Y: W deg in the world, the view's V) ...: playing` (W within 7.5 deg of V).
LA2. **It looks at what you framed.** The same play: `lens check at 0.5 s: eye ...; N m from the plan (M m from the
   world-axes reading), R m from the raw offsets; attached, in the anchor's frame; aim on screen +0.0x,+0.0y (...):
   looking at it`. The aim within ~0.05 of the middle = lockYaw false turns the look with the anchor (the round 17
   fix). Far off (e.g. +0.4) = the look still misses by the yaw: **report** the line and the anchor yaw.
LA3. **The fov now matches.** `lens fov measured F rad against the file's G`: F/G within ~5 % for every lens (0842
   gave cos(yaw) ratios: 0.33, 0.22, 0.40 when the look missed).
LA4. **Every lens, one place.** At one view try 12, 18, 50, 135 and 400 mm (Hold): each frames the same subject in
   the middle. A 400 mm view near the map's edge: `not started: ... the lens camera would stand off the map` and
   the status line says so (no play that ends by itself 0.4 s in).
LA5. **Empty land.** Pan to open land with nothing near the middle (desert hills): "Lens view" does not play; the
   status line (window footer) says "No object to attach the lens camera to near the middle of the view. Jump to a
   town, station or vehicle first." and the button's tooltip starts with "Last try: ...". Log: `lens not started:
   nothing to attach to within 1000 m ...` or `the best of N candidates (...) puts the centre P % of the frame off
   its middle (over 5 %)`.
LA6. **World speed.** Pause the game (speed 0). World "Your speed", Hold: the world stays paused while the camera
   holds (`lens playing ...; world player: speed 0 asked`, then `lens world: game speed read 0 (asked 0); the
   camera moved X m from 1.0 to 1.5 s (a hold)`). World "Paused", Move Orbit: does the camera circle with the world
   frozen? `camera moved X m (an orbit)`: X > 0 = the cutscene clock is real time (**report**); X = 0 = it stops
   with the game: then `the paused orbit's camera stands still ...: normal speed` and the status says so. World
   "Normal": the world runs at 1 meanwhile. After every end: `game speed back to the player's 0`.
LA7. **Never stopped for you.** Over 10 plays nothing ends by itself: every `lens end` is `ended (Esc or its end)`
   after you pressed Esc. An end before the check logs `ended T s in, before the attach check (... eye planned at
   x,y,z)`: **report** any. A `NOT attached` check line (eye at the file's raw offsets) shows the status "The lens
   camera did not attach to the object: press Esc to end it." and keeps playing.
LA8. **Orbit through the lens.** Move Orbit, 50 mm: one turn around the subject, always looking at it.

LT1. **Lens tour.** Camera tab, Lens tour: Every 10 s, Lenses All, "Lens tour". Expect a new subject every ~10 s, cut
   in, each through a lens of the set. Log: `lens tour on: a scene every 10 s, lenses all, world player`, per scene
   `lens tour scene N: <kind> <entity> (...) at x,y, lens M mm, after K tries`, then the play / check lines.
LT2. **Variety.** Over 10 scenes no two within ~400 m in a row (`seen lately` in a skipped line) and none at the
   map's edge. Vehicles: the camera rides along with them.
LT3. **Sets and interval.** Lenses Long: only 135 / 400 mm; Wide: only 12 / 18 mm. Every 5 s and 20 s.
LT4. **Esc ends it.** Esc once: `lens tour end after N scenes: ended (Esc or its end)`, `game speed back to the
   player's ...`, the window back, clicks on the map select again.
LT5. **Screenshot per scene.** Screenshot 1x, then the tour: one file per scene ~2.5 s in.
LT6. **Nothing to see.** On an empty new map: `lens tour scene skipped: nothing fitted in 8 tries (...)` and the
   status "The lens tour found nothing to look at on this map."

AG1. **Groups by climate.** Subjects tab, Animals: on the desert map the list is Lone cougar, Pair of cougars, Lone
   eagle, Eagles circling, Flock of gulls, A few gulls, School of salmon, Three schools of salmon. On a temperate
   map: Herd of deer (no elk exists in the game: deer is the herd), Wolf pack, Lone bear, Flock of cranes, ...
AG2. **A herd.** Temperate map, Herd of deer over open, flat land near trees: 6-12 deer close together. Log: `animals
   deer_herd (...): N of M places found in the view (...; rejected: steep K, roads or buildings K, ...)`, one `spawn
   deer at x,y: ok=true entity=E; score parts there: bias 0 forest 999 slope 0 slopeIs 0.1 ...` per deer.
AG3. **They live.** Add a Lone cougar on the desert map over flat open ground, wait 3 minutes. Log every second while
   watched: nothing, then `animals life cougar entity E: alive after 180 s (invalidTileElapsed 0)`. A death logs
   `life ... GONE after T s (last invalidTileElapsed X, movementType M, at x,y); score parts at its spot: ...` and
   an invalid tile first `on an invalid tile T s after the spawn`. **Report** every GONE line (with its score
   parts: a positive score that still dies means another rule).
AG4. **Steep or busy ground refuses.** Point the view at steep hills or a town: `No place in the view where these
   animals can live ...` and `rejected: steep N` / `roads or buildings N`.
AG5. **Flocks and schools.** Flock of cranes (one entity = one flock), Flock of gulls (8-20 birds close together),
   School of salmon over open water away from the shore (`No open water in the view for fish.` at a river bank).
AG6. **Cap 64; remove.** Add flocks of gulls until the status asks to remove first (64); "Remove the added ones":
   ours go, `gone already` for the ones the game took.

OR1. **Orbit circles what is in the middle.** Camera tab: hover Orbit: "Orbits the middle of the view." Click: the
   status says "Orbiting the middle of the view."; it circles the screen centre.
OR2. **After a jump.** Jump to a vehicle, hover Orbit: "Orbits the subject you jumped to."; move the camera away
   (pan to something else): the tooltip says the middle again and Orbit circles the new middle.
OR3. **DEV cutscene orbit.** With square_photo_mode_dev: Orbit over a building in the middle plays the cutscene orbit
   around it (`cutscene orbit: static anchor N ... M m from the view's centre`, M <= 40) and the orbit looks at it
   the whole turn (lockYaw false now); nothing within 40 m: `no static anchor within 40 m ...: the manual orbit`. A
   `cutscene orbit NOT attached` line no longer stops it: the status asks for Esc.

## Round 17: interesting views vary (built 2026-10-14, untested; PLAN.md "Round 17: interesting views vary")

IV1. **Every click a new view.** Subjects tab: click Skyline 8 times, then Train on a bridge 8 times on a save with
   one or two trains on bridges, then Anything with a few saved views. Each click lands on a different view: other
   subjects first (`interesting pick <kind> #n of m, view variant 0`, n counting up), then the same subject from
   new headings, heights and distances (`view variant 1`, `2`, ...: eye level, high, low in turn), never the
   identical view twice in a row. **Report** any variant that frames badly (inside a hill, facing away, too far).

## Round 16b: Lens, Foreground, Animals (built 2026-10-14, untested; PLAN.md "Round 16b")

No DEV mod needed (production). Log lines:
`make logs-grep PAT='\[PhotoMode\] (lens|foreground|animals) ' ARGS='--session last'`.

LN1. **Lens plays.** Frame a town or a station from ~300 m (Drone shot), Camera tab, Lens Telephoto (135 mm), Move
   Hold, Screenshot None, "Look through the lens". Expect: the UI hides, the subject stays in the middle at about
   the same size, the background (hills, buildings behind) clearly bigger and closer than in your view. Esc ends
   it; the window comes back. Log: `lens hold sqpm_lens_t_<s>_<e>_<h>: anchor N (<kind> entity M m from the centre
   ...) at x,y,z; the normal camera's fov measured F rad (the files assume 1.0472); 135 mm fovY 0.1771, size S m
   (the view's H m at d0 D0 m), D D m, elevation E deg (the view's ...), heading h ...: playing`, `lens playing N ms
   after the call`, `lens end: ended (Esc or its end) after T s, game speed back to the player's ...`.
   **Report**: did it look like the same shot through a long lens? Any jump or black frames at the start
   (streaming)?
LN2. **The fov is what the file says.** The same log: `lens fov measured F rad (X deg) against the file's 0.1771`
   (within ~10 % = fovY works as radians, vertical). And the normal camera's `fov measured` at the start (~1.047 =
   the 60 degrees the files assume; otherwise the sizes are off by that ratio: report the value).
(Round 17 replaced LN3's design: the keys' position turns with the anchor's yaw, the files use lockYaw false and
nothing stops a shot on its own; see LA1-LA8 below. The button is now "Lens view".)
LN3. **Attachment and locks.** `lens check at 0.5 s: eye ...; N m from the plan (world axes), M m from the
   yaw-turned reading (anchor yaw Y); tolerance T m: attached, world axes` = the locks keep the offset in world
   axes (the design). `attached, TURNED with the anchor's yaw` = the offsets turn with the anchor even locked
   (then the files need lockYaw false and the heading chosen against the anchor's yaw: report it). `NOT attached`
   = the anchor's type doesn't resolve (`ending it with the stop file: ...`; does the stop file end it?).
LN4. **Screenshot through the lens.** Screenshot 1x, then 2x. Expect one file per play in the screenshots folder
   showing the lens view (no UI). Log: `lens screenshot 1x requested at 2.5 s with the UI hidden: primer|shot|...`
   and the driver's `screenshot scale=...` line. **Report** whether the file exists and what it shows.
LN5. **Lenses and subjects.** Ultra wide (12 mm) on a train at a platform (jump "Train at a platform": the anchor
   is the train's carriage: `the subject's carriage ...`: does the camera ride along?), Super telephoto (400 mm) on
   a town from a low view (Horizon shot): the eye ~5 km back; does a hill block it (`raised to clear the terrain`,
   `clearance N m`)? Normal (50 mm) somewhere without buildings (anchors: trees / rocks: `ASSET_GROUP` in the anchor
   text?).
LN6. **Orbit.** Move Orbit with Telephoto: one slow turn around the subject (150 s; Esc earlier). Smooth? The start
   is always looking east (heading 0): how does the first frame feel against your view?
LN7. **Speed and input.** Start at game speed 4: during the play the game runs at 1, after the end 4 again (`game
   speed back to the player's 4`). Clicks on the map during the play select nothing.
LN8. **Esc twice / quickly.** Esc right after the start: ends cleanly, no stuck hidden UI, the button works again.

FG1. **Low cloud veil.** Weather tab, Foreground, tick "Low cloud veil" at a Drone view. Expect a soft veil over the
   view. Log: `foreground veil on: eye z Z; set cloudBase=... cloudTop=... cloudScattering=0.012 cloudCoverage=...;
   read back ...` (the read-back equal = the fields took). **Report**: visible? Too thick / too thin (screenshot)?
FG2. **The veil follows.** Zoom out / in by a few hundred metres: the veil stays around the camera (no log line per
   move; the cloud height sliders show the new values). Untick: `foreground veil off (checkbox): put back
   cloudBase=1500 ...`; the sky as before.
FG3. **Rain.** Tick Rain at a low view (eye under the cloud base). Expect falling rain. Log: `foreground rain on:
   cloud cover C -> 0.97 (the shader's drops fade in above 0.80 ...); read back ...; eye z Z under the cloud base`.
   **Report**: rain visible? From a high view (`ABOVE the cloud base`) none expected.
FG4. (Removed in round 17: Dust is gone; the user found it bad and too subtle.)
FG5. **Exits.** With both on: Esc (pause menu): everything goes and the player's clouds come back (`veil off
   (pause menu)`, `rain off (pause menu)`). Again with both on, untick "Light & weather override": the veil and
   the rain end (`veil ended: the cloud base was changed elsewhere`).
FG6. **Veil + rain order.** Veil on, Rain on, Rain off: the veil's cover stays (no rain); Veil off: the player's
   cover back.

AN1. **Species list.** Subjects tab, Animals: on the desert (dry) map the list is Cougar, Eagle, Gulls, Salmon.
AN2. **Add land animals.** Cougar, "Add to the view" at a Drone view over open land. Expect 1 cougar in view, facing
   the camera. Log: `animals cougar (::/animal/cougar/cougar.mdl, land): 1 of 1 places found in the view (...;
   rejected: ...)`, `animals spawn cougar at x,y: ok=true entity=N` (the callback: the line missing = no callback
   in a GUI state), 1.5 s later `animals check cougar entity N: at x,y,z (asked x,y: D m off), movementType M`.
AN3. **Birds and fish.** Eagle (flies over), Gulls (2); Salmon over a river or the sea (`No water in the view for
   fish.` over land). **Report** what shows.
AN4. **Remove.** "Remove the added ones": `animals remove cougar entity N: ok=true` and the animals vanish
   (`makeCustomEntityDestroyCmd` from a GUI script). Game animals stay.
AN5. **Cap.** Click Add 20 times: the status says to remove first after 32 (`not added: 32 added this session`).
AN6. **Save.** Save with added animals, load: they are ordinary animals (click one: the base animal window). Note
   whether they move on and leave like the game's own.

## Round 16 camera (built 2026-10-14, untested; PLAN.md "Round 16 camera")

The round 15 run's log was lost (PLAN.md "Round 16 camera"): CD1-CD6 still apply and run with these. Before
quitting the game, archive the log: `uv run tools/game_logs.py save`. Log lines:
`make logs-grep PAT='\[PhotoMode\] (cutscene fly|cutscene orbit|settle|hand-back|orbit |eye smoothness|tour flight)' ARGS='--session last'`.

CE1. **Aerials stays on the map (DEV mod on).** Start Aerials several times on the same map, each run to the
   chain's end (4 flights, ~5 min) or Esc after a while. **Report** any moment the void past the map edge shows
   (screenshot + time). Log: `cutscene fly plan (start): over <kind> at x,y, heading h turn t (...); map WxH m,
   view kept R m on the map`, then per hand-over `on from the last anchor, heading h turn t` or `no way on (...): a
   cut to a new area`; `cutscene fly i/4 ... sqpm_fly_h_k.lua`; the file's `cutscene fly file: data() heading h
   turn t angle a -> b`. Smooth through the turns? Any snap of the look at a hand-over (the next file starts on
   the last one's end heading)? How do the cuts to a new area feel?
CE2. **Variety (DEV on and off).** Start Aerials 4-5 times without moving the camera between starts: each start
   should go to a different place (DEV: `over <kind> at x,y` differs, `N areas shown lately avoided` grows; normal
   tour, DEV off: `tour flight new area` / `waypoint` lines spread over the map). Report if two starts in a row show
   the same area.
CE3. **Normal tour edge margin (DEV off).** Aerials with Look High, then Down, a few legs each on a small map if
   you have one: the waypoints (`tour flight waypoint x,y`) stay 2.5 km (High) / 0.9 km (Down) inside the map
   (or 30 % of it); report any view out over the edge.
CE4. **Orbit.** a. DEV off (or a view farther than 450 m): Orbit starts gently and reaches its speed in ~1.5 s;
   the button lets it slow to a stop in ~1.5 s (`orbit slowing to a stop (button)`, `orbit off (button: slowed to
   a stop)`), a second press stops at once. Smooth? Send `eye smoothness (orbit)`. b. DEV on, zoomed in (closer
   than 450 m) over buildings or trees, no jump before: Orbit plays the cutscene orbit around the nearest static
   thing (`cutscene orbit: static anchor E (MODEL_INSTANCE_LIST | ASSET_GROUP | CONSTRUCTION) N m from the view's
   centre`, `attached` / `NOT attached`, `pace around the subject`, `Invalid entity for attachment` count). As
   smooth as the Aerials cutscene? Does it look at the right thing?
CE5. **The fast camera after moves.** End a tour by a pan, by a right click and by the button; end a Wander; let
   an Orbit run zoomed far out and stop it. After each: a `settle (...): d a -> b m, pitch ... over 1.5 s` line
   where the view was far / flat, the camera gliding in for ~1.5 s, then `hand-back (settled)`. **Is the key pan
   normal now?** Does the glide-in feel right or unwanted? Pan during the glide (it goes on) and zoom during it
   (it stops: `settle ended by the player's zoom`). No `camera set with no move active` line. A High horizon shot
   must NOT settle (shots keep their view).
CE6. **Regression.** CD1-CD3 (world lock, hover, High default), CC2 (shots come back), Esc during a DEV flight
   (the camera back, the game speed as before), the pause menu during a settle (it stops).

## Round 15 (built 2026-10-14, untested; PLAN.md "Round 15")

From session `2026-10-14_0658_session`. Run with only Photo Mode (and its DEV mod for CD4). Log lines:
`make logs-grep PAT='\[PhotoMode\] (world lock|view tool|hover|hand-back|camera set with no move|cutscene fly)|Selected entity|Invalid entity for attachment' ARGS='--session last'`.
Round 14's CC1 is superseded (its switch let clicks through); CC2-CC5 still apply.

CD1. **No selection during tours.** Hide labels and hover on, an Aerials tour (now Look High by default), then
   Wander and Orbit. a. Click vehicles, stations, buildings while each runs: **nothing opens**, no `Selected entity`
   line (if one shows, nothing should open and the tour should go on). Log per move: `world lock on (automated
   camera move): selector filter set, entity windows off, player's features read`, one frame later `world lock
   check: entity windows off (the event reached the game)` (**report `STILL ON`**), at the end `world lock off
   (camera move ended)`; no `tool actions` lines any more. b. After each end: click a vehicle (its window opens), open
   a build menu and build a road piece (works). c. A right click during a tour ends it again (the action's back is
   back). d. `view tool: removed by another tool during a move, pushed again` lines: report them with what you did.
CD2. **Hover outline during tours.** As CD1, move the mouse over vehicles, buildings and stations: **report any white
   outline, tooltip or highlight** (the filter should remove the game's own; if an outline remains, it is drawn by
   the renderer itself and only a cutscene can hide it: then CD4's flights are the way). Also with "Hide labels
   during tours" unticked: do labels show during the tour?
CD3. **High is the default Look.** A fresh session: Tour tab, Aerials, Look shows High; Down and Horizon still work
   (one leg each).
CD4. **Cutscene aerial (DEV).** Enable `mods/square_photo_mode_dev` with Photo Mode. Look across open land or a
   town (the flight goes from the view's centre in the look's direction), Tour tab, Aerials, Start: up to 4 straight
   flights of 75 s, 250 m up, 20 degrees down. **Report**: smooth? does it pass over things (not terrain-bound)? any
   jump or turn at the keys (every 15 s) or between flights; UI / cursor / outline gone; Esc ends it (the camera
   back, the game speed as before). Log (send it all): `cutscene fly plan (start): heading h ...; anchor search
   MODEL_INSTANCE_LIST a/b ASSET_GROUP c/d CONSTRUCTION e/f` (which types have a fat instance), `cutscene fly 1/4
   ... anchors ...; legs a-b m`, the file's `[PhotoMode] cutscene fly file: data() heading h ...`, `cutscene fly
   attached | NOT attached: eye N m from the plan`, `cutscene fly key i at t s: eye ..., D m from above anchor i
   ...; look heading x (the file's y)` (D small = keys land on their anchors; the heading equal = the yaw lock keeps
   the look in world axes), `a second playCutscene REPLACES | does NOT replace the running one`, `hand-over: N
   frame(s) not playing, the eye jumped D m`, `cutscene fly end (...)`, `eye smoothness (cutscene fly)`; count of
   `Invalid entity for attachment` (`make logs-grep PAT='Invalid entity for attachment' ARGS='--session last'`).
   If the plan says `none` (no anchors), say what the map looks like there and try a town.
CD5. **"Fast movement".** After a tour ended by a pan, after Wander, and after a High horizon shot: pan with the keys.
   a. Is it too fast? b. Roll the wheel to zoom in a few steps: back to normal? (Yes = the hand-back distance is the
   cause.) Log: `hand-back (camera move ended | shot highhorizon): d=, the eye h m over the look-at point,
   d/height=, ...` per end / shot; **there must be no `camera set with no move active` line**. Tell whether an eased
   hand-back (the camera gliding in to a normal distance after a tour) would be welcome.
CD6. **Regression.** CC2 (shots come back), CC4 (Look Down centre fit), CB6b (free camera), V10.

## Round 14 (built 2026-10-14, untested; PLAN.md "Round 14")

From session `2026-10-14_0633_session`. Run with only Photo Mode (and its DEV mod for CC3). Log lines:
`make logs-grep PAT='\[PhotoMode\] (tool actions|view tool|hover|shot|centre fit|eye spike|eye smoothness|cutscene)|Selected entity' ARGS='--session last'`.

CC1. **No hover outline during tours.** Hide labels and hover on (as last time), an Aerials tour (Look High), then
   Wander and Orbit. a. Move the mouse over vehicles, buildings and stations while each runs: **report any white
   outline, tooltip or highlight**. Log: `tool actions off (automated camera move): no hover outline ...` at the
   start and `tool actions back (camera move ended)` at the end of each (exactly one pair per move). b. After each
   end: click a vehicle (its window opens), open a build menu and build a road piece (the tool works). c. Start a
   tour with "Hide labels during tours" UNticked: do the labels show during it (with no action at all they may
   not: report)? d. A right click during a tour no longer ends it (the action is off); camera input, Esc and the
   pause key still do. e. Only "Hide labels and hover" on, no move: is there still an outline when you point at
   things (that path keeps the empty action; report)?
CC2. **Shots come back to the same place.** Camera tab: Eye level, then High horizon, then Eye level: the second Eye
   level is exactly the first (log: `shot anchor new (first)`, then `shot anchor kept (kept)` twice). Then Low angle
   -> Horizon -> Drone -> Bird's eye -> Low angle: the same Low angle each time. b. Zoom or tilt by hand, then a
   shot: still the same place (`kept`). c. Pan or rotate by hand, then a shot: framed where you look now (`shot
   anchor new (camera moved | camera turned)`). d. A jump, a tour or Orbit, then a shot: a new anchor (`jump`,
   `camera move`).
CC3. **Attached orbit: no pulse (DEV).** As CB2a on a moving road vehicle (then a train). The file line now says
   `speed 31.37-31.37 m/s, locks yaw/pitch/roll true`. a. **Report** whether the pulse is gone and whether the
   orbit still circles the vehicle and rides along (dist ~130). b. Log: `cutscene orbit pace around the subject
   a-b m/s mean M spread S %` (even: mean ~31.4, spread a few %; round 13's keys would show a big spread), and the
   `cutscene orbit t=` lines' new `heading=` / `rel=`: with the yaw locked, `bearing` advances ~0.52 rad per 2 s
   whatever `heading` does (last time it gained what the vehicle turned). If the camera instead stops looking at
   the vehicle or leaves it: send the log (the locks mean something else; set them back in
   `content/mission/keyframes[/en]/sqpm_orbit.lua` `attach()`).
CC4. **Look Down: the centre fit.** An Aerials tour, Look Down, 2-3 legs over hills, a river and an industry, no
   input. **Report** where it jolted. Log: one `centre fit (tour): frames=N off>1m=K (p %) base height fits B, on
   water W; worst +X m at x,y g= base= water= d=` line per tour and `base=` / `water=` in every `eye spike` report.
   B close to K means the game's centre sits on the terrain's base height (without road / industry cuts): the
   solver can then use it (next round); W > 0 with the centre above 4 m tells the river's water level. Also: the
   tilt (look) should change more gently where the view meets a steep slope (the blend is now 1 s).
CC5. **Regression.** CB6a, CB7b (High still smooth: `spikes=0`), V10, the shots' note (Camera tab, under the shot
   buttons) fits in de / ja.

## Round 13 (built 2026-10-14, untested; PLAN.md "Round 13")

Since round 13 there is no Smooth camera (footer button, Camera tab section, `smooth trace` / `glide` lines):
W4, Z2's smooth camera part, CA1 and CA4 are obsolete. Log lines: `make logs-grep PAT='\[PhotoMode\] (view tool|camera
mode|tour|eye spike|eye smoothness|cutscene|back)|Selected entity|Cannot leave cockpit' ARGS='--session last'`.

CB1. **Hyper-sensitive camera.** The order that came before it last time: Free camera (Esc back), a tour, High
   graphics on, Hide labels on, close the window, play normally. a. Move around with keys, right-drag, middle-drag
   and the wheel after each step and **report the first step after which moving feels too fast** (or that it never
   does now). No `camera mode: mouse detached` line any more. b. If it still happens: untick High graphics (Settings
   tab) and try again (a lower frame rate?); then untick Hide labels (our view tool off: `view tool off (labels
   shown)`); then open and close the pause menu. Report which of those makes it go away. c. With only Hide labels
   on, right-click an open entity window or a build menu: it closes as usual (no `back (right click): nothing to
   end` line).
CB2. **Attached orbit cutscene (DEV).** First run (`2026-10-14_0606_session`): it played smoothly but around the
   map origin, with `Invalid entity for attachment` every frame: the map pointed at the road vehicle itself, not
   its carriage (fixed: PLAN.md "Round 13" item 4). Enable `mods/square_photo_mode_dev` with Photo Mode. a.
   Subjects: jump to a Road vehicle (a moving one), then at once Camera tab > Orbit: one turn of 24 s around the
   vehicle, 120 m out and 50 m up. Log: `cutscene orbit: subject road entity=E anchor=A (carriage 1 of 1) map
   {[9999999]=A} ... playing,` (A is not E now), the file's `[PhotoMode] cutscene orbit file: data() 25 keys (math)
   ...` (no timestamp prefix), `cutscene orbit attached: eye-subject ~130 m` or `cutscene orbit NOT attached: ...
   ending it: stop file played`, up to 16 `cutscene orbit t= eye= subject= dist= bearing= dz=` lines, `cutscene
   orbit end after N s (played), game speed back to the player's S (the cutscene left 1) | game speed S kept, ...
   eye-subject distance a-b m (an attached orbit: 130.0), attached | detached`, `eye smoothness (cutscene)`. b.
   **Report**: does the camera circle the vehicle and ride along with it (dist near 130), smooth? Does the bearing
   turn with the vehicle (`bearing=` while it turns a corner)? Any `Invalid entity for attachment` line
   (`make logs-grep PAT='Invalid entity for attachment' ARGS='--session last'`: count)? Cursor, outline, UI? Did it
   end early, and what did you press? c. A Train (the middle carriage: `carriage i of n`), a Ship and a Plane if
   the map has them. d. Static anchors: a Station, an Industry, a building from Subjects: either `not attachable
   (no carriage or model transform ...)` and the normal orbit, or a `model entity ...` anchor: then report whether
   it circled the place, or `NOT attached ... ending it` and **how long after that line the cutscene ended** (the
   end line's `after N s`: under 1 s means a second playCutscene replaces a running one; 24 s means it doesn't).
   e. After the end: the camera, UI, build menus (tool actions) and game speed as before (at speed 1, 2 and 4 /
   paused before the Orbit).
CB3. **Tours: spike reports and the cursor.** An Aerials tour of 2-3 legs and a "This place" tour, without touching
   the camera until you stop it with Esc. a. Copy every `eye spike` block (now `n/16`, at most 4 per tour, with
   `raw=` and `read-sent=`) and the `eye smoothness` lines. b. **Report** whether you saw a jolt and roughly when.
   c. During both tours: the mouse pointer over the map (hidden?), any white outline or tooltip, any `Selected
   entity` after a click.
CB4. **The game's Advanced Camera Tool (by hand, no mod needed).** Settings > Advanced > "Enable Advanced Camera
   Tool" on; in game a camera icon appears next to the free camera button. a. Open it, enter the free camera, fly
   to a start, press Insert (add keyframe), fly on, Insert again (3-5 keys over some hills), then Space (play).
   **Report**: is the playback smooth and free of the terrain; are the UI, the outline / hover and the mouse pointer
   gone during playback; can you save the path (and where the file lands: userdata `local/keyframes/`; send one
   file); does the window stay on screen during playback? b. Untick the setting afterwards if you don't want the
   icon. This decides PLAN.md "Round 13" route 1.
CB5. ~~io in the GUI state~~ **Closed** (`2026-10-14_0606_session`): `GUI state io=nil os=table load=function
   dofile=nil`: the GUI can't write a keys file; the prototype is removed (PLAN.md "Round 13" item 4). Aerials with
   the DEV mod is a normal tour again.
CB6. **Regression.** a. The footer: Free camera left, the screenshot group right; no Smooth camera anywhere (Camera
   tab: shots and camera moves only); de / ja fit. b. Free camera: Esc returns, the mouse turns the view as in the
   game bar's own free camera. **Passed** (`2026-10-14_0633_session`, user: "free camera button works that time,
   actually uses free camera"). c. ~~A right click during a tour, Wander or Orbit still stops it (Z2)~~ superseded by CC1d (round 14: the
   actions are off during moves). d. V10, Z6.

   Result (`2026-10-14_0633_session`): attached on a road vehicle (eye-subject 126.9-134.1 m, d2 max 1.04 m) and
   following, but "a strange glitchy movement like a pulse"; the bearing turned with the vehicle. Fixed in round 14
   (CC3).
CB7. **Aerials by default, Look High.** a. Open the Tour tab in a fresh session: Mode shows Aerials (Look Down,
   the Aerials rows shown). b. Look **High**: the drone climbs to about 1 km and looks down ~37 degrees at the land
   ahead; fly 2-3 legs over hills, towns and bridges: no jolt at all (log: `eye smoothness (flight)` d2 max under
   0.5 m, `spikes=0`; no `eye spike` line). Tell whether the view is worth having (or too high). c. The tooltip of
   High fits (de, ja).
   Result (`2026-10-14_0633_session`): b passed ("smooth": two High tours, `spikes=0`, d2 max 0.5 m), but "hover
   still active" (CC1).
CB8. **Look Down: what the jolts are.** An Aerials tour (Look Down) of 2-3 legs over hills and towns, no camera
   input. Say where it jumped (climbing, over a town, a bridge, a river). The log now gives one `eye spike` report
   per jolt (up to 8 a tour): in each, `centre=` z against `model z=` tells whether the game's centre left the
   height map (the 0606 kind: up to 3 m, expected now and then) and `read-sent=` whether it was input; the
   smoothness lines' `spikes=` count every jolt frame. A jolt with `centre` equal to `model z` and `read-sent` 0
   is a new kind: send the log.
   Result (`2026-10-14_0633_session`): "jerks before a big hill, over a factory, glitchy tilt over a river and a
   mountain"; 8 Down reports: 6 with the game's centre 1.6-8.4 m ABOVE the model where the ground under the
   centre fell steeply (a terrace / cut edge) or over a river, 1 the model's residual at 1.6 km; PLAN.md "Round
   14" item 2. Next: CC4.

## Round 12 camera (built 2026-10-14, untested; PLAN.md "Round 12 camera")

Log lines: `make logs-grep PAT='\[PhotoMode\] (view tool|smooth camera|tour|eye spike|eye smoothness|cutscene|click)|Selected entity' ARGS='--session last'`. No `ERROR` from `[PhotoMode]`.

CA1. **Click to glide (smooth camera).** a. Footer Smooth camera, then left-click a point on the map: the view
   glides there (eased start and stop, about 1-3 s, a small rise on long jumps) and ends centred on it at the same
   zoom, angle and tilt; log `smooth camera: glide to x,y (click onSelect)` or `(click onSelectNothing)`, then
   `glide arrived`. **Report** which callback name shows, and if a click does nothing (no `glide to` line: then
   report any `smooth camera click (...): no terrain point` line). b. Click a building, a train, water: it glides
   to the point under the cursor; nothing gets selected or outlined, no `Selected entity`. c. During a glide press
   a key / turn / zoom: the glide stops where it is (`glide ended by the camera input`) and the keys work as
   before. d. After a glide the keys, drag and wheel move the camera as in W4. e. The glide over hills: **report**
   whether the view bobs (`eye smoothness (glide)` line: d2 max). f. The Smooth camera tooltip mentions the click
   (en, de, ja fit).
CA2. **Tours: our tool on, no hover, no cursor.** a. Tick footer "Hide labels and hover" first (as in the session),
   open and close a build menu or an entity window (`view tool: removed by another tool`), then start an Aerials
   tour: the log line reads `tour: window hidden, game UI hidden, ... view tool on` and a `view tool on (...)` line
   comes right before it. b. Move the mouse over the map during the tour: **report** whether the cursor shows (our
   action asks for the base "None" cursor) and whether any white outline or tooltip appears; a click must not log
   `Selected entity`. c. The same with "Hide labels" off. d. After the tour (Esc / camera input): cursor, hover and
   click-to-select are back.
CA3. **Labels and the tool.** a. "Hide labels during tours" unticked, footer Hide labels unticked: during a tour
   the labels show as the HUD filter says (Z3a). b. **Report** if the labels vanish in tours only since this round.
CA4. **Smooth camera key start (unchanged).** The first key frame still jumps (round 11; the keyboard-speed lever
   is not used: PLAN.md item 1). Nothing to check beyond reporting whether the click-to-glide makes this matter
   less.
CA5. **Eye spike reports.** Tour, Aerials, 2-3 legs over hilly land (and one over flat land or water). a. Copy every
   `eye spike` block (the `eye spike n/12` line and the 4 `eye spike   #` lines after it) and the `eye smoothness`
   lines (now with `look d2 max`). b. **Report** what you saw at the moment of a spike if you noticed one (a jolt of
   the whole view, a bob up / down, a turn). Analysis: engine `eye=` vs `model=` (the game left the model) and
   `centre=` z vs `model z=`; a `CLAMPED` send; `blend=true`, a `lift` change or `guarded` growing in the frames
   before.
CA6. **Closed, prototype removed** (round 13: no `io` in the GUI state; CB5). Was: **Cutscene flight prototype (DEV).** Link and enable `mods/square_photo_mode_dev` (DEV, never upload) together
   with Photo Mode. a. Aerials, Start: instead of the tour a 20 s straight flight plays as a cutscene (UI hidden by
   the game). Log: `cutscene: GUI state io=... os=... load=...`, the file's `[PhotoMode] cutscene file: data()
   io=... load=... path=...` (no timestamp prefix), then `N keys from ...` (the dynamic keys were read) or
   `fallback still frame: why` (2 s above the map origin), `cutscene flight: 21 keys 20 s ... playing` or `NOT
   played: why`, and at the end `cutscene flight end after N s (played)`, `eye smoothness (cutscene)`. b. **Report**
   whether the flight was smooth (no bob over hills, no jerks), whether the cursor or hover showed, whether it ended
   early (and what you pressed), and copy the lines above. c. After the end: the UI and the camera are back as
   before; build menus work (tool actions back); the game speed is what it was. d. Disable the DEV mod afterwards.
CA7. **Regression.** Z1 (no hover with labels hidden), Z2 (a right click ends the smooth camera), W4 (smooth camera
   keys, Esc / pause key), V10 (tours stop on a pan / Esc / Space), Z6 (Aerials with no slow-down).

## Round 12 layout (built 2026-10-14, untested; PLAN.md "Round 12 layout")

Earlier steps that say "footer" for High graphics mode or Hide labels and hover (G, V, Z1, Z3) now mean the
Settings tab.

Y1. **Seven tabs fit.** The tab row shows seven icons (star, camera, eye, play, sun, cloud, gear) on one line
   inside the window, the window no wider than before; hover the gear: "Settings". **Report** a clipped or
   pushed-out last tab, or a wider window.
Y2. **Settings tab.** a. It holds High graphics mode and Hide labels and hover, each with its tooltip. b. Tick High
   graphics mode: the staged switch as before (the top-bar button's green contour); untick: back. c. Hide
   labels and hover works as before (Z1). d. Switch tabs while either is on: they stay on; the top-bar contour
   stays.
Y3. **Footer: one row, screenshot on the right** (English, default font size). a. Smooth camera and Free camera at
   the left, the camera icon and 1x / 2x / 4x flush with the right edge of the tab content (the same right edge as
   the separator line above). b. Hover the icon: "Screenshot"; the buttons' tooltips as before. c. The status
   line below the row, wrapping. **Report** (screenshot) if the screenshot group is not right-aligned (sits next to
   Free camera: the spacer did not stretch), if anything overlaps, or the window got wider.
Y4. **Footer in other languages / font sizes.** a. Russian: Smooth camera and Free camera wrap onto two lines at
   the left, the screenshot group stays on the right of the first line, nothing clipped. b. German or Italian:
   one line. c. Settings, Interface, font size Large (English): the two buttons wrap, the group stays right.
   **Report** any clipping or a wider window (Japanese at Large is the tightest: ~4 px over by estimate).
Y5. **Light tab.** a. Headings "Season" (Winter sun, Spring sun, Summer sun) and "Light angle" (Front light, Side
   light, Backlight), three per row. b. Override on, Spring sun: the Day value reads Day 80; the sun height sits
   between Winter and Summer at noon. c. Front light / Side light / Backlight act as before (L, K steps).
Y6. **Window height.** At 1080p, the tallest tabs (Tour Ground level, Light) fit on screen with the footer;
   **report** the tab that runs off the bottom, if any.

## Shutter (rev 2 item 2, built 2026-10-13, untested; PLAN.md "Rev 2" 2. *Shutter*)

Log lines: `make logs-grep PAT='\[PhotoMode\] screenshot|Screenshot' ARGS='--session last'` (the game's own
`Screenshot: wrote` lines too). Files: the game's `screenshots/` folder; measure them with `sips -g pixelWidth -g
pixelHeight <file>` and `ls -lh`. Start each X1 run from a fresh game start (the primer is once per loaded game).

X1. **Sizes and the tooltips.** Footer: a "Screenshot" label and "1x", "2x", "4x" buttons on one row under the
   checkboxes and the Smooth / Free camera buttons, on every tab. Hover each: the pixel sizes (e.g. "5120 x 2880" for
   2x at 2560 x 1440), the screenshots folder, "never in the picture"; 4x warns of the stall and the large file.
   **Report** the numbers shown vs your screen resolution: on a Retina Mac, are they the physical pixels (the file's
   size) or half? (If half, the tooltip and the `out=` log lie: the size has to be scaled.)
X2. **First shot of the session (primer).** Fresh game start, load a save, click "1x": status "Taking the
   screenshot..." then about a second later "The screenshot is in the game's screenshots folder." (round 11: the
   call blocks until the file is written; was "Saving the screenshot..."); the buttons greyed meanwhile. Log: `screenshot primer scale=1 ...`, then `screenshot scale=1
   viewport=WxH out=WxH`. **Report**: how many files appeared (one expected: the primer writes none; two means the
   primer is not needed and costs a file) and the game's `Screenshot: wrote` lines.
X3. **2x and 4x.** Then "2x": one file of 2x the viewport (no primer line this time); after it is re-enabled, "4x":
   the game stalls ~9 s, one file of 4x (~90 MB at 2560 x 1440). The buttons stay grey until about 12 s after the
   stall. Every press wrote exactly one file of `out=` size.
X4. **Cooldown.** Right after a 2x shot, try clicking a greyed button: nothing. After a 4x shot, as soon as the
   buttons come back, click "1x": a file is written (**report** if it is dropped: the cooldown needs to be longer).
   **Report** the delay from the click to the game's `Screenshot: wrote` per scale (log timestamps).
X5. **No UI in the picture.** Every file shows the 3D view only (no window, no game bar, no labels unless the
   game draws them in the world).
X6. **During other modes.** With the high graphics mode on: the shot is sharper. Hide labels and hover on: no labels.
   If reachable: a shot while a Wander / Orbit runs (the window stays open) is sharp and the move goes on.
X7. **Window closed right after a click.** Click "2x" in a fresh session and close the window at once: the real shot
   still follows a second later (`screenshot scale=2`), one file.
X8. **Languages.** German and Japanese: the row fits on one line (or wraps cleanly), tooltips fit.

## Phase 3: Light & weather (round 4, built 2026-10-13, untested; PLAN.md "Phase 3: Light & weather")

Log lines: `make logs-grep PAT='\[PhotoMode\] light' ARGS='--session last'`. Open the calendar widget's Weather
& Time panel (game bar) beside our window to watch the cycles.

L1. **Override on / off.** Light tab, tick "Light & weather override": `light override on: player's time=..
   timeMode=Dynamic cloud=.. weatherMode=Dynamic day=171 sun=0.000`; the calendar panel shows both cycles on
   "Custom". Untick: `light override off (checkbox): restored ...`, the cycles back as they were, the time and
   clouds as before (Dynamic may move on from there).
L2. **Presets.** Golden hour, Blue hour, Noon, Night, then Clear, Overcast, Storm, one at a time: each changes the
   picture at once (no fade?) and the tick box shows ticked. **Note**: does Storm rain (no rain field exists; the
   base "rainy" weather has full cover)? Do clouds change at once or slowly?
L3. **Sun model.** Golden hour on day 171 (June): `light preset golden: time=18:xx`; is the sun low and warm
   then? Season to day 351 (December) and Golden hour again (`time=15:xx`): still a low sun? If the light at
   those times is off (sun already set or still high), the game's sun doesn't follow the textbook model:
   note the time where it looks golden (then the presets become fixed times).
L4. **Step buttons.** Time `<<` `<` `>` `>>` move by 1 h / 10 min, the value between them updates; Clouds ±10 %;
   Season ±15 days (does the light / sun height change with the day of year?); Sun direction ±15° (**does the
   sun or the shadows turn? which way?** sunRotation's unit and effect are unverified). Note whether day of year
   and sun direction hold or snap back within a second (the game may reset the environment each frame).
L5. **Restore keeps the player's changes.** Override on, then in the calendar panel set the weather cycle back to
   Dynamic; untick: `kept weatherMode` (and `cloud` if it moved), the time cycle restored.
L6. **Pause menu and window.** Override on, close our window: it stays on. Esc: `light override off (pause
   menu)`, cycles back. Save from the pause menu: the save has the player's cycles.
L7. **Save while overridden.** Override on (Night, Storm), autosave (or F5 quicksave without the pause menu),
   quit with `pkill -9 TransportFever3`, start, load that save: `light: a save made while overridden; restored
   ...`, the cycles back on Dynamic. Variant: the mod removed before loading: the cycles stay "Custom" (expected,
   the tab's note says so); set them back in the calendar panel.
L8. **Freeze time.** Tick: the game pauses (game bar shows paused), `light freeze on (speed was N)`. Untick:
   speed N again. Tick, then press play in the game bar: `light freeze ended by the player`, the box unticks.
   Tick, Esc: `light freeze off (pause menu): speed N back`. Freeze + Hide UI + Space: UI back and the game runs.
L9. **Layout and languages.** Light tab in English, German and Japanese: the rows Time of day / Clouds / Season
   / Sun direction with their step buttons and values on one line each, the presets wrap, the note wraps, every
   button has a tooltip. Map editor: the tab renders (values may be "-"); clicks log no ERROR.

## Phase 4: Looks, weather over time, time-lapse, sun (built 2026-10-13, untested; PLAN.md "Rev 2" phase 4, LOOKS.md)

Log lines: `make logs-grep PAT='\[PhotoMode\] (look|weather|lapse|sun|light)' ARGS='--session last'`. The controls
are the Light tab's sections Looks, Weather over time, Time-lapse and Season and sun (between Presets and Adjust).

K1. **Looks load.** Start the game: no `sqpm_` errors in stdout (`make logs-grep PAT='sqpm_|environment'`). The
   calendar editor's Environment list (sandbox) shows no "Photo Mode look" entry. New game: the climate choice
   unchanged. Load time about as before (156 small env files since Soft background; 136 in round 11, 32 before).
K2. **Each look, Dry map, noon then evening.** Click each look: `look <key> on (button, climate dry by base)`;
   the picture changes at once (to confirm: probe T7 left it open) and clouds / day / sun stay as they were.
   Note per look whether it reads as intended (Hazy, Crisp, Misty at eye level, Mirror / Stormy on water,
   Moonlit at night, Dramatic, Storybook) and any value that is too strong / too weak.
K3. **Original look.** Back to the climate exactly (compare a screenshot before the first look).
K4. **Pause menu.** Look + Storm on, Esc: `weather ... stopped (pause menu)`, `look ... off (pause menu)`,
   `light override off (pause menu)`; the picture is the player's again. Save from the menu, reload: normal look.
K5. **Save while a look is on** (autosave or F5, then `pkill -9`, reload): `look: game start (marker ...)`; the
   climate's own look. Without the mod: the save loads with the normal look (nothing persisted).
K6. **Storm rolls in.** Clear sky to rain in 40 s, smooth (no steps)? At which cloud value does rain start (read
   the Clouds value shown when it starts)? End line: `weather storm done: ...; N steps, setEnvironment avg=..
   max=..` (cost; FPS during it). Clearing: the reverse.
K7. **Low clouds.** The deck comes down over 8 s: plausible, or do hills poke through / does it look broken?
   Note better cloudBase / cloudTop values if needed (`P.WEATHER.lowclouds`).
K8. **Time-lapse.** Sunrise and Sunset: the sun moves smoothly (no visible steps in the shadows)? Ends in the
   right light? Run the clock during a tour: the tour unaffected; Stop. With Freeze time on: does the clock
   still move (the command while paused)?
K9. **Seasons.** Winter sun: a low midday sun, long shadows; Summer sun: high. Do snow / foliage change with the
   day of year (dayOfYear may only move the sun)?
K10. **Sun calibration.** Noon (Presets), Winter sun. Look roughly north-ish, click Backlight: where is the sun
   relative to the camera (in front = correct / behind / left / right)? Turn the camera about 90 degrees right,
   Backlight again, same question. Report both answers and the two `sun back:` lines. Then at 09:00 and 15:00
   (time steps) Backlight once each: still in front (the clock is solar time and the sun follows the model)?
K11. **Side / Front light.** Side light twice (left, right), Front light: shadows across / away as expected.
K12. **Unknown climate** (a campaign map or a mod climate): the Looks section shows the note (no look buttons); the
   other sections work.
K13. **Layout and languages.** Light tab in English, German, Russian and Japanese: the look / weather / time-lapse /
   sun cells three to a row, long labels ("Ursprüngliche Stimmung") wrap inside their cell, every cell has its
   tooltip, the window stays ~460 px wide. **Report** whether the Light tab now runs past the bottom of the screen
   at 1080p (then the sections move to a tab of their own or a scroll area). The sun buttons at night: the status
   line says the sun is below the horizon.

### Round 11 looks (built 2026-10-14, untested; PLAN.md "Round 11 looks", LOOKS.md "Layers")

Log lines: `make logs-grep PAT='\[PhotoMode\] (look|tab)' ARGS='--session last'`; a look logs
`look <sky>_<water> on (button, climate ...)` with `orig` for a layer left alone.

K14. **Wild water on a river and on the sea.** A map with a river and a coast, Weather tab, Water: Wild water.
   Close to the river (eye level, Drone) and far: does it read as rapids / white water? The sea at the same time:
   too wild? Shoreline foam on river banks or only on coasts? Compare Stormy sea. **Report** "river: too weak /
   right / too strong" and "sea: ..." (tune `normalScale` 6, extinction x8 in `tools/gen_photo_looks.py` WATER).
K15. **Each sky look, dramatic and distinct?** Dry or Temperate map, noon and evening (golden hour), each sky
   look against Original: Hazy morning (golden haze, halo), Crisp & clear (deep blue, long views), Misty valley
   (at eye level: thick ground mist, veiled sun), Dramatic (huge sun, hard contrast, near-black shadows),
   Storybook (pastel sky, soft shadows), Moonlit night (at midnight: bright blue night). Water: Mirror (dead
   still), Crystal clear (the bottom near shores). **Report** per look: "too strong / right / still too weak",
   and any broken picture (blown-out white, black sky, banding).
K16. **Mixing.** Sky: Hazy morning, then Water: Mirror water: `look hazy_morning_orig on`, then
   `look hazy_morning_mirror on`; the haze stays while the water goes still. Sky: Dramatic: the water stays mirror
   (`dramatic_mirror`). Sky: Original: `orig_mirror`, the climate's sky with mirror water. Water: Original:
   `look orig_mirror off (button): back to ::/climates/...`. Clouds, time and sun unchanged through all of it.
K17. **Icon tabs.** Six icons in the tab row (star, camera, eye, play, sun, cloud), the selected one marked like a
   base tab; hovering each shows its name (Subjects, Camera, Views, Tour, Light, Weather) in English and German;
   **report** whether the tooltip shows on the indicator at all, and whether the icons look right (size, colour;
   a white square = a wrong path). The window keeps its width in de / nl / ja. Each tab fits a 1080p screen
   (the Light and Weather tabs especially).
K18. **156 look files load.** Start the game with the mod: no `sqpm_` / environment errors, load time about as
   before; the calendar editor's Environment list still shows no "Photo Mode look".
K19. **The look dropdowns.** Weather tab: Sky and Water open as dropdowns with Original first, each item with its
   tooltip, the closed box shows the chosen look's tooltip; a campaign or mod-climate map shows the note instead.
   The pause menu sets both back to Original (`look ... off (pause menu)`).
K20. **Soft background: a close subject against a dissolved background.** Dry or Temperate map, clear sky, noon
   and golden hour. Jump to a vehicle (or a building), Eye level or Low angle shot (the subject ~25-60 m away, the
   camera low), then Sky: Soft background (`look soft_background_orig on`). Expected: the subject stays nearly
   sharp and clear (a faint veil at most), everything a few hundred metres behind it fades into a bright, soft,
   glowing haze, brightest towards the sun (try Backlight); compare with Sky: Original and with Misty valley.
   Then Drone / Bird's eye: the whole map hazy (expected; the look is for close-ups). Also under Overcast.
   **Report** "subject: clear / too veiled", "background: too sharp / right / gone too soon", "veil: bright and
   glowing / grey and dull" (away from the sun and towards it), any blown-out white or banding; and the distance
   at which the background reads as soft. Tune in `tools/gen_photo_looks.py` SKY `soft_background`
   (mieScatteringScale 0.25 = how fast the veil grows, miePhaseG 0.45 = glow towards the sun vs elsewhere,
   hdrExposureDay / contrast), then `uv run tools/gen_photo_looks.py`. LOOKS.md "Soft background".
   **Superseded by K23** (round 12 retuned Soft background and moved it to the Haze dropdown).

### Round 12 looks (built 2026-10-14, untested; PLAN.md "Round 12 looks", LOOKS.md "Round 12")

Three dropdowns now: Sky (Original, Soft light, Dramatic, Storybook, Moonlit night), Haze (Original, Crisp & clear,
Hazy morning, Misty valley, Soft background), Water (Original, Mirror water, Crystal clear, Wild water). A look logs
`look <sky>_<haze>_<water> on (button, climate ...)` with `orig` for a layer left alone. In K14-K16 and K19 read
"Sky: Hazy morning / Crisp & clear / Misty valley" as "Haze: ...", "Stormy sea" as "Wild water".

K21. **Dramatic + Soft background.** Weather tab: Sky: Dramatic, then Haze: Soft background:
   `look dramatic_orig_orig on`, then `look dramatic_soft_background_orig on`; the big sun, deep blue sky and hard
   shadows stay while the distance softens. Haze: Misty valley, Water: Mirror water
   (`dramatic_misty_valley_mirror`), Sky: Original (`orig_misty_valley_mirror`): each change keeps the other two
   dropdowns. All three on Original: `look ... off (button): back to ::/climates/...`. The pause menu sets all
   three back.
K22. **396 look files load.** Start the game with the mod: no `sqpm_` / environment errors, load time about as
   before (156 files in round 11: compare the time to the main menu with an earlier session in `make logs-list`);
   the calendar editor's Environment list still shows no "Photo Mode look".
K23. **Soft background retuned** (the round 12 complaint: grey-brown murk, a grey-mauve sky). The same view as
   the user's screenshots (Dry map, the canyon from ~100 m up, low trees in front), then a low shot (Eye level or
   Low angle, a vehicle 20-80 m away). Clear sky and Overcast (0.7), noon and a low sun (sun 10 degrees: Sunrise
   time-lapse stopped early, or the time steps). Haze: Soft background with Sky: Original, then Sky: Soft light.
   Expected (model, camera ~100 m above sea level, level view): ~6 % veil at 50 m, ~11 % at 100 m, ~44 % at
   500 m, ~68 % at 1 km; the veil bright (as bright as sunlit ground or brighter on every side, warm at a low
   sun), the sky still blue above ~10 degrees, far cliffs visible but soft. On high ground (camera 300 m above
   sea level) about half as strong (expected, the aerosol is packed low). **Report** "subject: clear / veiled",
   "background: too sharp / right / too soft", "veil: bright / grey", "sky: coloured / washed out", and the map's
   height if known. Tune `soft_background` in `tools/gen_photo_looks.py` HAZE (`mieScatteringScale` 0.27 = strength,
   `mieScaleHeight` 0.4 = how high it reaches, `miePhaseG` 0.1), then `uv run tools/gen_photo_looks.py`.
K24. **Misty valley fixed.** Haze: Misty valley, eye level in the morning, valley or coast: thick white mist
   (model: ~18 % at 100 m, ~62 % at 500 m), the sky above blue; from Bird's eye (1-2 km up) the map only lightly
   veiled. Under Overcast the same mist (not greyer). **Report** "too thick / right / too thin", "white / grey".
K25. **The reshaped sky and water looks.** Sky: Soft light (lifted shadows, low contrast, a soft veiled sun),
   Dramatic (now with Crisp & clear's deep blue), Storybook (no rosy haze now); Haze: Crisp & clear (long, sharp
   views; with Sky: Original the sky is less deep blue than round 11's Crisp & clear: pair it with Dramatic);
   Water: Wild water under the Storm preset (darker, harder: Stormy sea's overcast light). **Report** any look
   that lost its character in the split.

### Round 15 looks and sliders (built 2026-10-14, untested; PLAN.md "Round 15 looks", LOOKS.md "Round 15")

Weather tab: Sky (Original, Soft light, Dramatic, Storybook, Moonlit night, Golden glow, Cold blue, Faded film, Neon
dusk), Haze (+ Dust storm), Water (+ Tropical turquoise), each dropdown between `<` and `>`. Light tab "Adjust":
Time of day, Season and Sun direction sliders between `<` / `>` step buttons, the value after them.

LS1. **The new looks read as named.** On the Dry or Temperate map, noon and a low sun (Sunset time-lapse stopped
   early): Sky: Golden glow (golden light on the land, warm shadows, a glowing sunset; the sky may turn paler or a
   little greenish-cyan at noon: report it), Cold blue (a pale, bluish sun, cool shadows, quiet sunset), Faded film
   (soft contrast, faded colours, warm lifted shadows), Neon dusk (magenta / violet sky around sunset and into the
   night; by day a slight magenta cast). Haze: Dust storm (orange-brown veil, dim orange sun, brown sky; the
   distance gone within a few km). Water: Tropical turquoise (cyan water on Dry / Temperate / Subarctic; on
   Tropical its own colour, clearer). **Report** per look "distinct / too weak / too strong / broken colour", with
   a screenshot when off; tune in `tools/gen_photo_looks.py` (absorptionScale is each sky look's strength, Dust
   storm's mieScatteringScale 0.2 and mieAbsorptionScale 0.06).
LS2. **1076 look files load.** Start the game with the mod: no `sqpm_` / environment / texture errors other than the
   known `Could not find texture ''`; time from start to the main menu and `Enter Game Asynchronously` / `Init game
   took` about as before (396 files: 4-5 s, 6.7-8.5 s, 10.7-12.6 s on "New Game - desert";
   `make logs-grep PAT='Enter Game Asynchronously|Init game took|Main menu is ready'`). The calendar editor's
   Environment list shows no "Photo Mode look".
LS3. **Arrows beside the look dropdowns.** Sky `>` from Original: Soft light (`look soft_light_orig_orig on`), `>`
   again: Dramatic; `<` from Original: Neon dusk (wraps to the last); `>` on Neon dusk: Original
   (`look ... off (button)`). The dropdown shows the stepped look; Haze and Water rows the same; each arrow keeps the
   other two layers. Tooltips "Previous look." / "Next look.". The rows fit the window (no wider window, in de / ru
   too).
LS4. **The sliders look and fit.** Light tab: three slider rows, each `<` slider value `>`, the slider about 140 px,
   the handle draggable, the value text not clipped (de "21. Sep.", fr "21 sept.", ru "21 июн"); the window no
   wider than before. Tooltips on the slider, its value and both arrows. **Report** a slider that shows vertical,
   has no width, or overlaps the value.
LS5. **Live, smooth, no stutter.** Drag the Time of day slider slowly across the day: the light follows while
   dragging (about 12 updates a second), no hitch, no window flicker; the value text follows the handle. Let go: one
   log line `light slider time: time=hh:mm ...`, not one per step. Drag Season (the sun's height changes: noon in
   December vs June) and Sun direction (the shadows turn round; 0 = the climate's own direction). `make perf` /
   SQPERF: `window_render` count should not climb while dragging.
LS6. **Release off the slider and keyboard.** Drag a slider and let go outside the window: within half a second one
   final log line (the settle); the value stays where it was let go. Click a slider and use the arrow keys (if it
   takes focus): the value steps (10 minutes, 1 day, 1 degree) and a final log line follows each pause.
LS7. **Sliders and the rest.** While Run the clock is on, drag Time of day: the time-lapse stops (`lapse run stopped
   (replaced by a click)`) and the time follows the slider. After Backlight / Side light / Front light the Sun
   direction slider shows the new rotation; after the `<` / `>` step buttons the slider moves to the stepped value.
   Untick the override: time, day and sun come back, the sliders show them.
LS8. **Regression: looks and sliders across the pause menu and a load.** A Round 15 look on (e.g. Neon dusk + Dust
   storm + Tropical turquoise, the longest marker key with Moonlit night: `moonlit_night_soft_background_turquoise`),
   save, load: back to the climate (`look: game start ...`), no error. Open the menu while dragging a slider: the
   override's values come back, no stuck slider.

## Round 16 settings (built 2026-10-14, untested; PLAN.md "Round 16 settings", LOOKS.md "Round 16")

Logs: `make logs-grep PAT='\[PhotoMode\] (setup|look legacy|light .*cloudScattering)' ARGS='--session last'`.

- **RS1 Save and reload a setup.** Weather tab: Dramatic + Hazy morning; Light tab: Golden hour. Settings tab >
  Save new: a name field opens with "Setup 1"; type "custom golden 1", Enter. Log `setup save id=1 look=dramatic/
  hazy_morning/- ...`, a frame later `setups written n=1 saved=true ms=` (one `Saved settings to settings.lua`). Quit
  the game, start it, load another save: the dropdown lists "custom golden 1" (`setups loaded n=1`), its tooltip
  names the looks, the time and the date.
- **RS2 Rename, Overwrite, Delete, the cap.** Rename (Enter keeps the new name, Esc in the field keeps the old one:
  check that Esc there doesn't open the pause menu), change the look and Overwrite ("Setup saved."), Delete. Save new
  stays disabled at 30 setups with the tooltip "At most 30 setups".
- **RS3 Load.** Untick the override, Original looks, unfreeze, High graphics off, labels shown; pick a setup saved
  with a look, a time, frozen, High graphics and hidden labels on; Load: the look, the time / date / sun / clouds,
  the freeze, High graphics mode (the ~1 s stall) and hidden labels all come back; status "Setup loaded: ...". Load
  one saved without High graphics while it is on: it stays on.
- **RS4 The accidental Esc.** A look, a time, a cloud density and Freeze time on, High graphics on. Esc: everything
  goes back at once (as before); close the menu, open the window: the status line says "The menu put your own light,
  weather and look back. Settings > Restore last setup brings this picture back." Settings > Restore last setup:
  the look, the values, the freeze and High graphics mode return. Log `setup last (pause menu): ...` before `hq
  off(pause menu)` and `look ... off (pause menu)`, then `setup restore last: ...`.
- **RS5 The last setup in the save; add / remove.** After RS4's Esc, Save the game from the pause menu, load it:
  `setup last from this save: ...`, Restore last setup works. Remove the mod and load that save: no warning, the
  game's own weather and time (the Checks 5 / P11 check, now with `last` and setups present).
- **RS6 Clouds slider and rain.** Weather tab > Adjust > Clouds: drag from 0 to 100 %. Rain shows from about 80 %,
  fully at 100 % (the rain shader, findings environment.md "Rain"); `<` / `>` move 10 %. With Cloud height at 500 m
  the rain falls only below the deck.
- **RS7 Cloud height and density.** Cloud height 100 m to 4000 m moves the whole deck (low: clouds over the hills);
  Cloud density 10 % thin and soft, 400 % thick and heavy (does it show at all? the visible effect is inferred).
  Untick the override: `light override off (checkbox): restored ... cloudBase=... cloudTop=... cloudScattering=0.005`.
  A setup saved with them brings them back.
- **RS8 Legacy.** Weather tab > Sky: Legacy is the last item (after Neon dusk; `>` from Neon dusk reaches it).
  Picking it: `look legacy on (button, climate dry by base): ::/climates/dry/dry_old.env` (no `look legacy ERROR
  environment not found`: the ResName is inferred) and a different picture (brighter, paler sky, more distant haze).
  Pick a haze: Legacy ends (the Sky shows Original). Try it on a temperate, subarctic and tropical map. Esc: back to
  the climate.
- **RS9 Night lights.** 22:00, a town: Original vs Moonlit night vs Neon dusk: the lit windows and street lamps
  brighter in the two night skies (x2 / x2.5).
- **RS10 Setups while High graphics mode is on.** High graphics on, Save new: `setups written n=... saved=false` (not
  saved while boosted). Untick High graphics: the restore saves (`hq restore stage 3/3 ... (marker cleared,
  saved)`); restart the game: the setup is there and Settings > Graphics shows your own values.
- **RS11 Window height at 1080p.** At 1920 x 1080 with the Large text size: the Weather tab (three sliders plus the
  Foreground section) and the Settings tab (setups and options) fit on screen; the cell buttons wrap long
  translations inside their cells (de: "Letztes Setup wiederherstellen").
- **RS12 A look only.** No override, pick Storybook, Esc, Restore last setup: the look comes back and the override
  stays off (the day cycle is not switched to Custom).

## High graphics with geometry / terrain / grass (built 2026-10-14, untested)

From the DEV risky test (`2026-10-14_2019_r18-test-risky`: the three passed alone, shadows crashed alone).

- [x] HQ1 (the log part passed twice in `2026-10-14_2150_r19-test`; the denser look not reported): High graphics mode on: the log shows 6 `hq stage i/6` lines, stages 4-6 `geometryQuality`,
  `terrainQuality`, `grassQuality` one each, no crash or `StaticBuffer` assert. Grass and far detail look denser.
- [ ] HQ2: Untick: 6 restore stages (grass first, textures last), your values back in Settings. Repeat on / off 5x.
- [ ] HQ3: Esc with it on: the one-call pause-menu restore (all 9 keys together) doesn't crash.

## Crash checks (offline audit 2026-10-12, plans/square_photo_mode/PLAN.md "Crash safety")

After each: no `ERROR` line from `[PhotoMode]`, no assert or crash dump
(`make logs-grep PAT='Assertion|Fatal error|\[PhotoMode\].*ERROR' ARGS='--session last'`).

C1. **Followed vehicle removed.** Jump to a bus, Follow on, then sell that bus (Line Manager / vehicle window). The
   camera stops following; log `stoppedFollowAction: follow / cockpit ended by the game` (or `follow` turns off on
   the next orbit / tour frame). Click Follow again: grey "Jump to a vehicle or a person first.", no follow.
C2. **Ridden vehicle removed.** Cockpit on a bus, sell it from the Line Manager (open it from the game bar while in
   the cockpit, if reachable; else sell it via a second vehicle window opened before). Expected: back to the map,
   `stoppedFollowAction: ...`, no crash. Note whether the game fired the event at all.
C3. **Stale subject.** Jump to a truck, send it to a depot (vehicle window), wait until it is in, then Cockpit and
   Follow: grey "Jump to a vehicle first." / "Jump to a vehicle or a person first.", no
   `cockpit on` / `follow on` line. Same after selling it and letting the id be reused (build a few roads).
C4. **Tools and the free camera.** With the bulldozer, then a road tool active, click Cockpit, Follow, a Shot and a
   subject. Then the game's own Free Camera (game bar radial menu) and, if the window is still visible there,
   the same buttons. Note what happens; any crash here means guarding the buttons while a tool / free camera
   is active.
C5. **The game's own cockpit.** Vehicle window > Enter Cockpit, then a subject button and Esc in our window (if
   visible). Then our Cockpit, and the vehicle window's Enter Cockpit on another vehicle. No crash; note the camera.
C6. **Exits during moves.** During a Tour glide: Esc (`tour off (pause menu)` or `(window)`), the window X
   (`tour off (window)`), the top-bar button (`tour off (window)`, `window closed (button)`). During Orbit while following, the same. During the
   cockpit: Esc leaves it (`cockpit off (pause menu)` or `(window)`).
C7. **Double clicks.** Double-click the camera button fast: the window opens and closes (or stays as the second
   click left it), no hitch, no `hq` line. Double-click "Highest graphics": on, then off again before the stages
   ran (`hq on cancelled (toggle) before stage 1` or `hq off(toggle) after stage K of 3`), the toggle ends off,
   your graphics. Toggle on, then Esc during a stage's stall: if `...: a switch is running, off queued` shows,
   `hq off(pause menu)` must follow at once and no further `hq stage` line.
C8. **Corrupt safety-net marker.** Quit the game. In `settings.lua` (`~/Library/Application Support/Steam/userdata/
   <id>/3493540/local/`, inside `mainMenuState = { ... }`, next to `square_better_minimap = { ... }`) add
   `square_photo_mode = { boosted = true, orig = { shadowQuality = 0, grassQuality = 0, textureQuality = "x", ssrQuality = 1 } },`
   with Reflections set to High and Grass to High in Settings beforehand. Load a save: `marker found: restoring
   ssrQuality=1 | kept ...` (the broken texture value and the old marker's shadows and grass ignored; Shadows and
   Grass unchanged), marker cleared (the next load logs no marker line). Variant: the
   value `"junk"` instead of the table: `marker without original values, clearing`. Other mods' entries in
   `mainMenuState` (Better Minimap's) stay.
C9. **Camera extremes.** Save a view zoomed out to the limit at a map corner, one at eye level; go back to each.
   Bird's eye then Orbit. The camera never jumps off the map; `setCameraData ERROR` never logs.
C10. **Map editor.** Photo mode on in the map editor: subjects, Shot, Orbit, Tour (nothing to show), Save view;
   then Esc. No crash.
C11. **Languages.** German and Japanese: every tab renders (Views tab with 0, 3 and 12 views (scrolling), "View %d", "%d s",
   "At most %d views" tooltip). A render error would log `tab <key> render ERROR` / `button render ERROR`.

## Regression checklist (every release)

1, 2, 3, 6, P1, P3, P10, P11, F1 (incl. the long session), F3, F5, F6, G1, G2, G3, G3h, G5, G6, G9, G10, G11,
G12, G13, G14, G15, G16, G18, G20, G21, G22, G23, G24, L1, L6, L7, L8, K3, K4, K5, a few of S1-S12, C1, C3
and C7.
