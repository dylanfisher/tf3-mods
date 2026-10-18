# Findings: Environment, weather, light and cutscenes

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## Live environment edits apply at once and hold (verified in game 2026-10-13)

- `local e = api.gui.rendering.getEnvironment()`, change `e.atmosphere.<field>`, `api.gui.rendering.setEnvironment(e)`
  applies at once: `cloudCoverage` (0, 0.3, 0.48), `dayOfYear` (15, 172) and `sunRotation` (+pi/2) read back the
  new value in the same frame and one frame later, and held until the next change seconds later (dayOfYear 172 and
  sunRotation 1.571 still set ~5 s later), **even with the weather cycle on Dynamic**.
- Only these atmosphere fields are live-settable (`type.d.tl` `Environment.AthmostphereParams`): `cloudCoverage`,
  `cloudBase`, `cloudTop`, `cloudScattering`, `dayOfYear`, `sunRotation`. Dry map values: cloudBase 1500,
  cloudTop 3600, cloudScattering 0.005, dayOfYear 171, sunRotation 0; live cloudCoverage 0.782 with Dynamic weather.
  The probe set cloudBase / cloudTop / cloudScattering only back to their own values (restore), so their visible
  effect is unconfirmed (Photo Mode "Low clouds", TESTING.md K7).
- `api.cmd.makeGameSetCloudCoverageCmd(c)` sets the sim's `WORLD.cloudCoverage` (read back 0.48 one frame and 3 s
  later). Seen too: after the environment set alone, the sim's value followed it about 2 s later (0 and 0.3; no
  command sent), so the cause is inferred.
- The weather cycle event `makeScriptingSendEventCmd("", "CloudCoverage", "SetMode", { weatherMode = "Constant" })`
  works: the game script's `weatherMode` read Constant 2 s later (it was Dynamic).
- Restore (the saved environment copy, the saved sim cloud cover and weather mode) brought everything back.
- Evidence: `.cache/logs/2026-10-13_1924_sqpq` (`[SQPQ] T6 ...`), Photo Quality probe T6, Dry map.

## A mod's environment file is registered and can be switched to, rendering only (verified in game 2026-10-13)

- A mod's `content/environments/x.env.lua` is listed by `api.res.environmentRep.getAll(false)` and `getAll(true)`
  (the same 14 entries) as `<modId>::/environments/x.env` (`square_photo_quality_probe::/environments/sqpq_test.env`,
  id 13), next to the base climates (`::/climates/<c>/<c>.env`, isToolEnvironment false), the `*_old` "(Legacy)"
  envs, `subarctic2.env` "(Test)" and the model editor envs (those three groups isToolEnvironment true).
  `environmentRep.find(<that ResName>)` returns the id. No restart needed.
- `api.gui.rendering.setEnvironment(api.res.environmentRep.get(id))` switches the rendering environment: its `name`
  became the file's ("SQPQ test") and held 3 s later, while `api.gui.game.getEnvironment()` stayed
  `::/climates/dry/dry.env`: nothing reaches the save. Switching back the same way with the game's ResName restored
  the Dry environment. (`api.gui.game.setEnvironment(resName)` would persist the choice into the save: Photo Mode
  never calls it.)
- **A switch resets the live atmosphere values to the file's**: cloudCoverage went from the live 0.782 to the
  file's 0. Read the six live fields before a switch and set them again on the new environment afterwards.
- Whether the switch visibly changed the picture was not reported (Photo Mode TESTING.md K2).
- Evidence: `.cache/logs/2026-10-13_1924_sqpq` (`[SQPQ] T7 ...`), Photo Quality probe T7.

## `isToolEnvironment` only hides an env from the calendar editor's list (from the game files 2026-10-13)

- The base reads `isToolEnvironment` only in the calendar editor's Environment ComboBox
  (`base/content/gui/game_bar/game_bar_widgets.tl` ~609-620: `if not env.isToolEnvironment`). Climates for a new
  game come from `.clima.lua` files (`environment = "dry.env"`), which never name a mod's env file, so a mod env
  file never shows as a climate choice either way. Photo Mode's look files set it true (hidden from that list, as
  the base `*_old` and model editor envs).

## Cloud cover runs 0..1 in TF3 (from the game files 2026-10-13, inferred)

- `base/content/game_mechanics/game_time/game_time.script.tl`: the weather states' means are sunny 0.5 (sigma
  0.2), cloudy 0.5 (0.3), rainy 1.0 (0.3), each draw clamped to 0..1. The wiki's "0.0 to 0.5, rain at about 0.45"
  (`docs/wiki/modding/environment/environments.md`) is TF2-era. Supporting it in game: the Dynamic weather's live
  cloudCoverage read 0.782 (T6 above, past the wiki's 0.5 top). Where rain starts: from the rain shader, 0.8 (next
  entry, inferred; Photo Mode TESTING.md K6 checks it).

## Cutscenes from a mod: `api.gui.mission.playCutscene` (verified in game 2026-10-13)

- `api.gui.mission.playCutscene("<modId>::/mission/keyframes/x.lua", true, map)` (form A: the path without the
  language folder, `resolveLanguageFolder = true`; the file in `content/mission/keyframes/en/x.lua`, the campaign's
  format) plays from a mod GUI script: the call returned in 4-7 ms and `isCutscenePlaying` was true at once.
- While it plays the game hides the UI root (`react.game-ui-root` invisible) and gives it back at the end; it set
  the game speed from 0 (paused) to 1 (the probe paused it again afterwards). It leaves 1 after the end: a play
  started at speed 4 ended at 1 (`2026-10-14_0606_session`, `game speed 4 -> 1`), so restore the player's speed
  read before the play (the base cutscene task sets `params.gameSpeed or 1` in `onComplete`).
- The camera goes where the keyframes say, by eye and centre **in world coordinates** (eye 0, 0, 400, the centre
  82.5, 0, 343.5: the file's fallback at the map origin), not bound to the terrain; `getEye` / `getCenter` follow
  the cutscene while `getCameraData` keeps the player's view. After the end the camera is exactly where it was
  (eye moved 0.0 m).
- The keyframe file's `data()` runs **without `api`, `ug_require`, `log` or the GUI state's globals** (a global
  set by the probe was not visible; `api` nil: "attempt to index global 'api'"), so it cannot read the current
  camera: only static positions or entity-relative ones (the `entityToEntityMap` argument) are possible.
- 5 runs (fov 3x, roll, fade): 3 played their ~5 s, 2 ended after ~2.5 s (inferred: player input ends a cutscene).
  The last run's end was not logged.
- Evidence: `.cache/logs/2026-10-13_1924_sqpq` (`gzcat ... | grep '\[SQPQ\] T9'`), Photo Quality probe T9 (fov,
  roll, fade). Not run: attach, T10-T12.
- **The keyframe file is loaded again at every `playCutscene`** (read from the same log 2026-10-14): before each of
  the 5 plays the file's top-level code ran again (`chunk loaded: ...`) and its `data()` counter restarted at
  `data() call 1`. So `data()` runs per play, not once per game: a file it reads can change between plays.
- In that state `print` works (its lines reach stdout.txt without a log prefix), `_` is a function, `api`,
  `ug_require` and `log` are nil (plain global reads), and `rawget(_G, "...")` raised (the probe's `SQPQ_T9=ERR`).
  Whether `io`, `os`, `load` or `debug` exist there is not yet seen (moot now: the GUI side has no `io`, below).
- **The GUI state has no `io` (in game 2026-10-14)**: a GUI script (Photo Mode's window module) logged `io=nil
  os=table load=function dofile=nil debug=table require=function` (`.cache/logs/2026-10-14_0606_session`, `[PhotoMode]
  cutscene: GUI state ...`). So a GUI script can't write a file for a keyframe file to read: no file channel from
  the GUI to a cutscene. `load` there compiles strings in the GUI's own state only, and the keyframe file's state is
  a fresh one at every play with no globals of the GUI (above). Dynamic camera paths need the entity map (below).
- **Its chunk name is the file's absolute path**: an error inside `data()` read `[string "/Users/.../staging_area/
  square_photo_quality_probe/content/mission/keyframes/en/sqpq_fov.lua"]:38: attempt to index global 'api'`. A
  file can find its own folder from an error message (no `debug` needed), so with `io` it could read a file another
  Lua state wrote next to the mod folder.
- Keyframe camera fields (campaign files, e.g. `urbangames_campaign_mission_08` `MISSION_08_CUTSCENE_ROCKET_START.lua`):
  `position` is the eye in world coordinates, `angle` the heading, `pitch` the look's elevation (negative = down:
  the probe's fallback eye 0, 0, 400 with pitch -0.6 looked at 82.5, 0, 343.5), `fovY`, `roll`, `speed`, `time`; two
  keys at the same time make a cut; `attachment = { entity, group, lockPitch, lockRoll, lockYaw }` makes `position`
  relative to an entity mapped by `playCutscene`'s third argument. The base cutscene task fires
  `disableToolActions` true before and false after (`mission/tasks/cutscene/cutscene.tl:38`, `:51`).
- **The entity map** (game files 2026-10-14): `playCutscene(file, true, { [idInFile] = liveEntity })`; the campaign
  maps the file's two ids to the first carriages of two moving trains (`urbangames_campaign_mission_01`
  `mission/mission_story.tl:86-97` `getEntityToEntityMap`; keys with `attachment = { entity = 33846, group = 0,
  lockPitch = false, lockRoll = false, lockYaw = false }` and positions of a few metres,
  `keyframes/en/MISSION_01_CUTSCENE_OUTRO_A.lua:116`); the base task also fires `clearToolStack` first. The binary
  has "Invalid entity for attachment". So a fixed keyframe file can fly a path around an entity the GUI maps in,
  with no file channel. The map's keys are plain integers (the file's ids), its values live entities
  (`api/tealdef/api/gui.d.tl:753-754` `entityToEntityMap? : {Engine.Entity : Engine.Entity}`); mission_08 maps
  `{ [167181] = rocketState.rockets[1].rocketEntity.entity }` (`mission_story.tl:890-897`), a custom model spawned
  by `custom_entity_util.spawn` whose transform is `MODEL_INSTANCE_LIST.fatInstances[1].transf`
  (`base/content/game_mechanics/fun_elements/custom_entity_util.tl`). Mission_01's two mapped vehicles are Mardi
  Gras floats, ROAD vehicles from a road depot (`mission_story.tl:2625`), mapped to their `CARRIAGE_LIST.carriages[1]`:
  every campaign anchor is an entity with a transform of its own (a carriage or a model), never a transport vehicle.
- **A transport vehicle's own entity is not a valid anchor (in game 2026-10-14)**: Photo Mode mapped road vehicle
  95565 itself (`{ [1] = 95565 }`): the engine logged `ERROR Invalid entity for attachment` (`train_fever/src/Game/
  UI/Actions/CameraAction.cpp(180): GetTransform`) every frame, 34,075 times in 24 s, and the eye flew the keys'
  raw offsets around the map origin (eye 120, 0, 50 -> -120, ...; the vehicle 750-1003 m away). The cutscene still
  played to the end (no api stops one: `api.gui.mission` has only `playCutscene`, `isCutscenePlaying`,
  `getCutsceneElapsedTime`; Skip is the native `IA_SKIP_VOICEOVER_AND_CUTSCENE`). The playback itself was very
  smooth (1361 frames, eye second difference max 0.72 m, rms 0.05 m) and not bound to the terrain. Inferred cause
  of the wrong anchor: `api.engine.getComponent` hands components as userdata, and a `type(c) == "table"` check
  skipped the vehicle's carriage list. Evidence: `.cache/logs/2026-10-14_0606_session` (`grep 'cutscene orbit'`).
  Open: whether a construction or town building can be one. A second `playCutscene` replaces a running one (0842,
  "Cutscene attachments" below).
- **A static MODEL_INSTANCE_LIST anchor can fail to attach too, silently (in game 2026-10-14)**: session
  `2026-10-14_2332_r20-test` (sub-arctic map, Photo Mode's DEV cutscene flight): five flights over the same first
  anchor 47716 (a MODEL_INSTANCE_LIST at -1752,-5078,4) each put the eye 5349-5350 m from the plan at 0.4 s, i.e.
  at the world's origin, the keys' raw offsets (the user saw a view "cut off" the map); unlike the transport
  vehicle above, the log has no `Invalid entity for attachment` line. Other MODEL_INSTANCE_LIST anchors in the
  same session attached (1-60 m). Inferred: some instance lists have no transform the attachment resolves (a
  multi-instance group, as with the 226-instance anchor in this file). Photo Mode now leaves an anchor whose flight
  did not attach out of every later plan.
- **A carriage anchor works; unlocked offsets turn with the vehicle (in game 2026-10-14)**: Photo Mode mapped a
  road vehicle's carriage (session `2026-10-14_0633_session`, `cutscene orbit`): the eye stayed 126.9-134.1 m from
  the vehicle (the keys' 130 m) and rode along with it, no `Invalid entity for attachment`, `eye smoothness
  (cutscene)` d2 max 1.04 m. With `lockYaw = false` (and pitch / roll) the offsets TURNED with the vehicle: the
  eye's bearing from the vehicle gained what the vehicle's heading turned (bearing - heading +0.50 to +0.53 rad per
  2 s, the orbit's own 0.52; the bearing alone +1.11, +1.01 in a bend, +0.01 in the opposite one). Inferred:
  `true` keeps that axis out of the entity's turn (the camera tool's "Lock Yaw / Lock Pitch / Lock Roll"
  checkboxes, binary strings); Photo Mode round 14 tries it (TESTING.md CC3). Round 17 (0842): refuted for the
  position (it turns with the anchor locked too); `lockYaw = true` keeps the camera's LOOK in world axes
  ("Cutscene attachments" below).
- **A key's `speed` is the camera's speed in m/s there (binary + campaign files 2026-10-14; the effect in game
  inferred, strong)**: CameraAction moves the camera along its spline by distance (`m_data->splineDist`), and the
  Advanced Camera Tool's key list has the columns "Time", "Speed" and a button "Auto Set Speed". Every campaign
  key holds exactly the chord to the next key over the time to it (MISSION_01_CUTSCENE_OUTRO_A: 14.034655 m in 15 s
  -> speed 0.935644; the key ending a segment before a cut repeats that segment's; a key between two segments the
  mean, MISSION_07_CUTSCENE_BONUS_COMPLETE 38.787 = (39.531 + 38.042) / 2; the last key its segment's). Keys whose
  speeds don't match their spacing pulse: Photo Mode's orbit (25 keys a second apart, 31.4 m segments, every speed
  1) played with a "glitchy movement like a pulse" (session `2026-10-14_0633_session`) and an eye acceleration rms
  of ~200 m/s2 against the 8 m/s2 of an even circle, what a cubic segment with end speeds of 1 m/s gives (peak 6 L
  / T^2 = 188 m/s2). So set every key's speed as Auto Set Speed does. TESTING.md CC3 checks that it is even then. The game's Advanced Camera Tool keeps its keys in the same structure (map-camera.md "The
  Advanced Camera Tool").

## Cutscenes: attachments per key, the skip key, input (game files + binary 2026-10-14; the chain untested)

- **Different entities in one file**: the campaign attaches keys of one file to two entities
  (`urbangames_campaign_mission_01` `MISSION_01_CUTSCENE_OUTRO_A..D`: keys 9-10 and 13-14 on 33846, 11-12 on 20790,
  the rest unattached in world coordinates), but always as separate shots: each pair of keys shares one attachment,
  and a cut (two keys at the same time) sits between shots on different entities. No base file interpolates from a
  key on one entity to a key on another; what the engine does then is unknown (Photo Mode's round 15 DEV cutscene
  aerial measures it: TESTING.md CD4).
- **The skip key is Esc**: the game's key log lists `IA_SKIP_VOICEOVER_AND_CUTSCENE (Esc or rightshoulder)` (every
  session's start, e.g. `2026-10-14_0606_session`); the binary's `CameraAction.cpp` strings name `OnSkipCutscene`,
  `IA_MENU`, `IA_BACK`, `gamePause`, `gameCycleSpeed`. So a player can end a mod's cutscene with Esc (inferred: the
  action handles it natively), and a playing cutscene is a native camera action (`action-camera`) that takes the
  map's input (inferred; gui.md "`disableToolActions` outside a cutscene").
- **No api stops or replaces a cutscene** (`api.gui.mission`: `playCutscene`, `isCutscenePlaying`,
  `getCutsceneElapsedTime`); whether a second `playCutscene` replaces a running one is open (round 15 logs it).

## Cutscene keys: the full field list, fovY as focal lengths, no look-at; the `en/` copy is the one loaded (game files + binary + log 2026-10-14)

- Fields the binary reads for a camera key (strings right after `CameraAction.cpp` "Invalid entity for attachment"):
  `time`, `attachment`, `position`, `angle`, `pitch`, `roll`, `fovY`, `skyRotation`, and in `attachment` `entity`,
  `lockPitch`, `lockRoll`, `lockYaw` (the campaign also writes `group = 0`). The file's other blocks: `fades`
  (`fadeIn`, `duration`, `fadeOut`), `subtitles`, `voiceOvers`, `portraits`, `music`, `environmentParams` (a list of
  `{ params = { <~40 atmosphere fields> }, time }`: a cutscene can set the whole atmosphere over time, which a live
  `setEnvironment` can't). **No look-at / target field and no focus**: a key's look is its own angle and pitch;
  aiming at an entity needs the key's position relative to it (attachment) and the angles pointing back.
  `base/tealdef/mission/tasks/mission_dialogue_data.d.tl` CameraFrame lists the same minus attachment.
- **`fovY` is the vertical fov in radians and the campaign's values are focal lengths on a 24 mm high frame**,
  fovY = 2 atan(12 / mm): 1.0472 (60 degrees, 20.8 mm: most keys), 0.6606 (35 mm), 0.5451 (43 mm), 0.4296 (55 mm),
  0.3948 (60 mm), 0.2805 (85 mm), 0.7108 / 0.761 / 1.0808 (32 / 30 / 20 mm). The Advanced Camera Tool's strings
  have "Camera Focal Length", "{} mm" and "{angle} Field of View". The normal camera's own fov: 60 degrees
  (inferred: the campaign's usual key and every animal model's `cameraConfig.positions[].fov = 60`); Photo Mode's
  Lens measures it with `world2Screen` and logs it (TESTING.md LN2).
- Keys are sorted by time (`std::is_sorted ... kf0.time < kf1.time`), and the binary asserts `result.length > .0f`
  next to the spline code: two keys at the same position with time between them may hit it (untested; Photo Mode's
  lens holds drift 3 % to stay clear).
- **Only `keyframes/en/x.lua` is loaded** for `playCutscene("<mod>::/mission/keyframes/x.lua", true)`: every
  "chunk loaded" line of the T9 probe named the `en/` copy (`.cache/logs/2026-10-13_1924_sqpq`), never the copy in
  `keyframes/`. The campaign ships only `en/` and `de/` (other languages fall back, inferred). A mod needs only the
  `en/` copy (Photo Mode's 1131 Lens files are `en/` only).
- Evidence: binary strings (`strings TransportFever3`), campaign keyframes (`.cache/game/mods/release/
  urbangames_campaign_mission_0*/content/mission/keyframes/en/*.lua`), the T9 log above.

## Cutscene attachments: the key's position turns with the anchor's yaw even locked; `lockYaw = true` keeps the look in world axes (game log 2026-10-14_0842_session; lockYaw false inferred)

- Photo Mode's Lens (keys with `lockYaw / lockPitch / lockRoll = true`, attached to static model entities) logged
  the eye 0.5 s in against two readings: the file's offset in world axes and the offset turned by the anchor's yaw
  (its first fat instance's transform). The turned one matched (0 / 6 / 16 / 0 / 37 / 26 m) where the world one
  was off by 7-1703 m, for anchors at yaws 0.21, -1.25, -1.36, -2.95, 1.88 rad: **the key's position is in the
  anchor's frame, locks or not** (0633's carriage orbit, locks false, turned too).
- The look did not turn: the fov measured through `world2Screen` (an aim point and one above it, assumed on the
  axis) came out the file's times cos(phi), phi the anchor's yaw: 0.0578 vs 0.1773 (tan ratio 0.325, phi 71.0 deg;
  yaw 71.6), 0.1042 vs 0.4711 (phi 77.5; yaw 78.1), 0.4678 vs 1.1760 (phi 69; yaw 78), 0.1698 vs 0.1773 (yaw 20),
  1.5205 vs 1.5708 (yaw 12). So with `lockYaw = true` the camera stood in the anchor's frame but looked in world
  axes, past the anchor by its yaw (user: "it doesn't look where I'm pointing, seems random"). "Lock Yaw" locks
  the CAMERA's yaw to the world. Inferred: `lockYaw = false` turns the look with the anchor too (0633: locks false,
  the carriage stayed in view through bends); Photo Mode round 17 uses it, TESTING.md LA2 checks it (the anchor's
  screen position in the `lens check` line).
- Tele holds with eyes kilometres out (400 mm: 1.8-5.3 km) ended by themselves 0.4-0.5 s in, before any check
  (08:49:05, :11, :13); inferred: the eye left the map (Photo Mode round 17 keeps the eye on the map and logs
  every early end's reason).
- A second `playCutscene` while one plays replaces it: the stop file played over a lens shot and the play ended
  0.5 s in (0842); the round 17 lens tour cuts between scenes this way.
  Round 18 note (1729): the DEV flight chain's own check logged "a second playCutscene does NOT replace the running
  one" (the elapsed time ran on, 74.51 -> 74.53 s) in the same frame the eye jumped 1071 m to the new flight's
  first anchor; the lens tour's scene cuts in that session played their new views (`lens check` 0-82 m from each
  plan). Open which reading is right (the elapsed counter may simply carry on).
- Speed: the cutscene set speed 1 from the player's 0 every time (0842); whether its camera clock runs at game
  speed (a paused world freezing the camera) is open (Photo Mode logs "lens world", TESTING.md LA6).

## The game's screenshot key works during a cutscene (game log 2026-10-14_1729_add-money-100m, verified)

- While Photo Mode's DEV flight cutscene played (`cutscene fly 1/4` from 18:50:07, `fly 2/4` from 18:51:22, the
  end at 18:52:04), the game wrote four screenshots (`Screenshot: wrote ...img_45.png` at 18:51:20, img_46 / 47 /
  48 at 18:51:33 / :46 / 18:52:03), 5120 x 2880 each (2x of the 2560 x 1440 screen: `sips`), with no Photo Mode
  screenshot request in the log: the player's F9.
- F9 is `IA_GAME_SCREENSHOT` (every session's key log: "F9 or touchpad + rightshoulder"); the only handler is the
  base `FreeCamOptions` (`gui/main/free_cam_options.tl:19-23`: `takeScreenshot(2)` on any non-console build),
  mounted in GameUIProxyRoot outside the UI root a cutscene hides. So that component's input actions still fire
  during a cutscene (inferred for its Back / Menu back too). Screenshots never contain the UI (map-camera.md).
- For a player: during a Lens view, lens tour or any cutscene, F9 (unless rebound in the key settings) saves a 2x
  picture. Photo Mode round 18 says so in the Lens notes and adds its own buttons (gui.md "Wrapping a base recipe").

## Cutscene attachments: the position turns with the anchor's pitch too; round 18 unlocks every axis (game log 2026-10-14_1729; inferred)

- A 400 mm lens hold attached to a climbing plane's carriage (keys `lockYaw` false, `lockPitch` / `lockRoll` true)
  checked 15.6 s into a lens tour: the eye 269 m off the plan (the plan turns the offset by the anchor's yaw only)
  and the plane 3.43 screen heights below the middle ("NOT looking at the anchor"); static anchors in the same
  session sat at +0.00 (`lens check` lines). Read: the key's position turns with the anchor's pitch as it does
  with its yaw (0842, locks or not), while `lockPitch = true` keeps the look level, so at 1.8-9 km out a few
  degrees of grade swing the eye hundreds of metres and the look misses: the user's "super telephoto following a
  bus sometimes points the camera down in a weird way, perhaps when the bus goes down a hill".
- Photo Mode round 18 sets every lock false (the camera rigid in the anchor's frame: the 0633 carriage orbit, all
  false, kept its vehicle in view) and skips static anchors leaning over 2 degrees. Expected: the anchor stays in
  the middle and the whole view tilts with a vehicle on a grade. TESTING.md R18-5 checks it.

## A cutscene camera follows its anchor rigidly: no smoothing (binary + game log 2026-10-14_2019_r18-test)

- The camera key fields the binary reads (the strings after CameraAction.cpp's "Invalid entity for attachment") are
  `time`, `attachment`, `position`, `angle`, `pitch`, `roll`, `fovY`, `skyRotation`, and in the attachment
  `entity`, `lockPitch`, `lockRoll`, `lockYaw`: no damping, lag, smoothing or ease field among them (the binary
  has `Damping` and `Ease*` names, but not among these key strings). The locks keep the LOOK in
  world axes, not the position (0842 / 1729 above).
- So an attached camera is rigid in its anchor's frame: every bump and turn of a vehicle shows at once. The user
  (Photo Mode round 18, a lens orbit on a bus carriage, 54.7 s) found it "fairly jerky if it goes up/down small
  hills or makes sharp turns". A long lens magnifies it: a 1 degree pitch is a third of a 400 mm frame (fovY 3.4
  degrees). No easing is possible from a keyframe file; Photo Mode round 19 offers a static anchor beside the
  vehicle's way instead ("Steady").

## The game pauses again just after a skipped cutscene (game log 2026-10-14_2150_r19-test; cause inferred)

- Photo Mode's lens views read the game speed when a play starts and put it back at the end. In that session a
  lens view ended with the game running (`game speed 1 kept (the player's: 1)`, 22:15:46), and the next play 5 s
  later read speed 0 (22:15:51); the same at log lines 9144 -> 9148. The user: "game keeps pausing after coming out of
  cut scenes, even if it was playing before". Every one of those ends came 0.6-9 s in, so the player skipped them
  with Esc; Photo Mode itself sent no speed command in between (no freeze, no pause menu event).
- Inferred: the Esc that skips the cutscene also reaches the game's pause handling once the cutscene is over (the
  binary's `CameraAction.cpp` names `gamePause` and `gameCycleSpeed` beside `OnSkipCutscene`; base `game.tl` declares
  `gamePause` on GameUIProxyRoot, "available even when Game UI is not visible"). Not seen how many frames after the
  end it lands.
- Photo Mode round 20 watches the speed for 2.5 s after each end of its cutscenes and puts the player's speed back
  once if it changes to anything but that or the speed the end left; the log line "the game speed went to 0 N ms
  after the end" measures the delay (TESTING.md R20-6).

## A telephoto from kilometres out looks washed out and coarse: haze and distance LOD (game files + game log 2026-10-14_2150_r19-test; inferred)

- Photo Mode's lens kept the player's frame height, so a long lens stood far out: 135 mm on the view's 513 m frame
  played at D 3.6 km, 400 mm at 800 m would stand 5.3 km out. The user: "telephoto often looks weird in lens view,
  more so with the looks set".
- Haze and fog grow with the distance the light travels (below, "Haze can't be near + clear middle + far"):
  from kilometres out the whole subject sits behind that much air, so it washes out and takes the sky's colour; the
  looks multiply mie / fog up to x10 (`plans/square_photo_mode/LOOKS.md`), which makes it far stronger.
- Models switch their level of detail by distance in metres, not by the zoom: an `.mdl`'s `lods` have
  `visibleFrom` / `visibleTo` in metres (the draft horse: 350-1200 m for its last level), and the geometry tiers'
  `lodDistanceScaling` written from a mod showed no effect (map-camera.md "Geometry tiers"). A telephoto from far
  out shows the far, coarse levels (or nothing, past `visibleTo`).
- Neither can be cut per shot from a mod (a cutscene key has no LOD or fog field; switching the env costs a reload).
  Photo Mode round 20 keeps the lens eye within 1.5 km (`pm_lensdef.lua` `L.FAR_D`): a long lens frames tighter
  instead.

## The dev console has no `io` either: keyframe files can't be written at runtime (user, 2026-10-14)

- The user ran `print(io, ...)` in the in-game dev console: `io` is nil there too (as in GUI scripts, 0606 above).
  Neither a GUI script nor the console can write a keyframe file for a cutscene to read, and the keyframe file's
  own state has no api (the "Cutscenes from a mod" section). The dynamic cutscene-file route is closed: cutscenes
  stay static files whose keys attach to entities the GUI maps at each play.

## `api.gui.rendering.spawnDust` is a small transient puff; the user found it bad (2026-10-14)

- `spawnDust(bbMin, bbMax, transf)` (gui.d.tl; the base's only use puffs a collected mission object,
  collect_entity.tl:130) makes a short puff in the box. Photo Mode round 16b spawned one every 0.7 s between the
  camera and the subject as a foreground "Dust"; the user: "Dust looks bad and too subtle, get rid of it" (round
  17 removed it). Not a usable foreground or haze effect.

## Photo Mode's 32 look environments all switch in game (seen 2026-10-14)

- Session `2026-10-14_0055_session` (Dry map): every one of the eight round-4 looks was switched to many times
  (`look <key> on (button, climate dry by base): square_photo_mode::/environments/sqpm_dry_<key>.env`), back to
  `::/climates/dry/dry.env` with `ok=true`, no `look ... ERROR`; the live cloud, cloud base / top and day were
  carried through every switch. Weather animations cost 0.01-0.02 ms per `setEnvironment` (max 0.07 ms).
- `Texture error: Could not find texture ''` appeared at load (base files have `waveFoamTex = ""`) and twice at
  switches (01:08:06, 01:10:54) to an env with `waveFoamTex = ""` after one with foam: a warning, nothing broke
  (inferred: an empty texture name is looked up).
- The user's verdict on the picture: "some looks aren't different enough" (round 11 pushed every look further).
- Evidence: `gzcat .cache/logs/2026-10-14_0055_session.log.gz | grep PhotoMode`.

## Hundreds of mod env files cost no measurable load time (game logs, read 2026-10-14)

- The same map ("New Game - desert", same seed) loaded with Photo Mode active before it had look files and with
  its 396 look env files (1.9 MB, round 12), timed by the game's own lines (`Application startup` -> `Main menu
  is ready`, `Enter Game Asynchronously: N ms`, `Init game took: N s`):

  | Session | Look files | Start -> main menu | Enter game | Init game |
  |---|---|---|---|---|
  | `2026-10-13_0610_session` | 0 | 5 s | 6.67 s | 10.65 s |
  | `2026-10-13_1755_session` | 0 | 4 s | 7.36 s | 13.54 s |
  | `2026-10-13_1915_session` | 0 | 4 s | 7.04 s | 15.18 s |
  | `2026-10-14_0606_session` | 396 | 5 s | 8.48 s | 12.64 s |
  | `2026-10-14_0633_session` | 396 | 4 s | 7.13 s | 10.68 s |
  | `2026-10-14_0658_session` | 396 | 4 s | 6.65 s | 11.25 s |
  | `2026-10-14_0733_session` | 1076 | 3 s | 5.62 s | 12.73 s |

  The spread between runs of the same build (6.3-8.5 s, 10.6-15.2 s; one-off outliers to 14.7 / 24.9 s in
  `2026-10-14_0055_session` / `_0434_session`) is larger than any difference the files make. Staging-area mods
  aren't read from the content cache (`Reading content cache from json` lists only release and mod.io mods), so
  every start reads them. Inferred: env files are small Lua tables parsed at load (`environmentRep.getAll` lists
  them all), a few hundred cost well under the noise. Photo Mode ships 1076 since round 15 (4.5 MB): its first
  session with them (`2026-10-14_0733_session`, the round 15 build: `RegisterRecipeInner(886, PhotoModeSlider)`, the
  files written at 07:19Z) loaded the same map in 5.62 s / 12.73 s, inside the spread (one run; read 2026-10-14).
  So 0, 396 and 1076 files show no difference; nothing says where a cost would start, so file counts far past the
  tested 1076 are an extrapolation.
- Evidence: the table's sessions, `make logs-grep PAT='Enter Game Asynchronously|Init game took'`.

## No colour grade in an env file; the tone mapper's saturation follows its contrast (game files 2026-10-14)

- The last pass (`rendering/programs/shaders/hdr/compose.fs`) only multiplies by the exposure, adds the bloom and
  runs the AMD tone mapper (`util/tonemappers.glsl` `amdTonemapperOpt`): no tint, saturation, white balance, LUT
  or vignette uniform. A "noir" (black and white) or sepia grade has no env field.
- The tone mapper's colour saturation is tied to its contrast: `saturation = contrast` after
  `contrast = mix(contrast, 1, 0.25)`, and the colour ratio (colour / peak) is raised to it (dark pixels: ratio ^
  (0.75 c + 0.25)). So `light.hdrContrastDay[1]` (base 1.3-1.4) is both the curve and the saturation: 0.8 gives
  ratio ^ 0.85 (faded colours, a flat curve), 1.9 gives ^ 1.68 (vivid). Bright pixels are pushed towards white by
  the crosstalk term either way. Inferred from the shader (Photo Mode's Faded film / Neon dusk looks rely on it,
  TESTING.md LS1).
- Colour therefore comes from the light: the ozone layer (`absorptionCoeff` x `absorptionScale`, a 25 km layer in
  `sampleMediumRGB`) sits in every transmittance to the sun, so a coefficient that absorbs blue warms the sunlight
  on the land and in the sky (more so at a low sun), one that absorbs green turns twilight magenta (the real
  "Chappuis" purple); the Rayleigh colour (`rayScatteringCoeff`: the sky, and the sunset colour through its
  smallest channel), the ambient fill (`ambientDayColor` / `NightColor`, added to every lit surface,
  `util/lighting.fs:122`) and `sunsetBoostScale` / `Param` (sky brightness near the horizon: boost =
  (s p (1 - x) + (1 + p) x) / (x + p), x = the sun's height sine; `atmosphere/common.glsl` `calcSunsetBoost`).
  The visible size of each in game is unverified.
- Water colour is a texture: `water.depthColorTex`, a 64 x 16 DXT1 gradient from shallow (white) to deep
  (`climates.zip`): dry and temperate (subarctic points at temperate's) teal-green (#6ad6b4 ... #183029), tropical
  cyan-blue (#7beef6 ... #081c29). Another climate's texture by absolute path (`::/climates/tropical/depthColor.dds`)
  recolours the water without a texture of one's own (Photo Mode's Tropical turquoise; in game unverified).

## What an env file controls; no depth of field or blur anywhere (from the game files 2026-10-14)

- An env file's blocks (`base/content/climates/*/*.env.lua`, wiki `modding/environment/environments.md`):
  `atmosphere` (sky and air: Rayleigh / Mie / ozone scattering, aerial perspective `fogScaleLow` / `High`, sun
  and moon size, bloom and brightness, sunset boost, clouds, day), `light` (post-processing: ambient day / night
  tint, HDR exposure, contrast and tone-map curves for day, night and overcast, latitude), `water`, `shadows`,
  `skyBox` (textures). Only the six `AthmostphereParams` are live (above); everything else needs a whole-file
  switch, so mixing looks needs one file per combination (Photo Mode round 12: sky x haze x water, 4 x 99 files, ~4.7 KB
  each).
- No depth-of-field, focus, tilt-shift or blur field exists: not in the env files, not in `api/tealdef` (no fov /
  dof / blur / bloom on the camera or rendering api), not in cutscene keyframes. The final pass
  (`rendering/programs/hdr_compose.prog.lua` -> `shaders/hdr/compose.fs`) reads only the frame and the bloom blur
  (`texBlurred`, bindings 0 and 1; no depth texture), applies exposure, bloom, the AMD tone-mapper with the env's
  contrast / shoulder / mid values and gamma. The bloom chain (`hdr_scale` -> `hdr_blur_h/v` -> `hdr_blur_compose`)
  copies the whole frame without a threshold (`scale.fs`), so `texBlurred` is a blurred copy of the full picture.
  Caveat (2026-10-14): compose adds `texBlurred` on top of the frame (`col += bloomCol`), so at full strength it would
  double the brightness; its input or strength is probably set by the engine (not in the files). Unverified.
- One post pass does have depth: `rendering/programs/ssr_apply.prog.lua` -> `shaders/misc/ssr_apply.fs` binds the
  lit frame (`colorTex`), the depth buffer (`depthBufTex`, linearised with `u_ssao.nearFar`), a blurred mip chain
  (`blurredTex`, `textureLod` up to `maxNumMips`) and `View` / `Light`; it always copies the frame (and the rain
  lens drops) and adds reflections only when `ssrOn`. A depth of field fits there (probe built 2026-10-14);
  whether the pass and its mip chain run with Reflections off in the graphics settings is open.
- Cutscene keyframes (`urbangames_campaign_mission_*/content/mission/keyframes/*/*.lua`): `camera` keys are
  position, angle, pitch, roll, fovY, speed, skyRotation (plus entity attach / lock fields); `environmentParams`
  hold the whole `atmosphere` block (mie, rayleigh, fog, sun bloom, moon: ~40 fields, far more than the six live
  ones) interpolated over time, no `light` or `water` fields. Whether a cutscene applies them is unverified.
- GUI stylesheets have a `blurRadius` property (base `main_menu.css.lua`: the full-screen window and a campaign
  card), a backdrop blur; it is not in the api `StyleSheet` record (inline `makeStyle` can't set it), so it needs
  a class rule. A screenshot through `api.gui` capture leaves the UI out (Photo Mode's shutter), so a GUI blur band
  would only show on screen.

## Shaders: a mod can't replace a base shader; manual install only, PC only (game files + REP 2026-10-14)

Supersedes "mods may ship them on PC" (same day): the shipping part holds, a base-shader override does not.

- **No override from a mod folder (inferred, consistent with a published mod's own statement).** TF3 resources
  are namespaced per mod: `/x` in a mod means that mod's own file, `::/x` the base game's, `<modId>::/x` another
  mod's (wiki `modding/general/resourcetypes.md` 76-93); a mod env file shows up as its own entry
  `<modId>::/environments/x.env` next to the base ones, never in their place (above). The engine names its
  post-processing programs without a mod (`rendering/programs/hdr_compose.prog`, `ssr_apply.prog`, ... in the
  executable's strings), and the shader cache records every source as `base/content/rendering/programs/...`
  (`shader_cache/cache.lua` `dependencies`, Steam userdata `.../3493540/local/shader_cache/`). The mod.io mod
  "Realistic Environment Pro" (REP, mod.io 6415745, by lorenzo.sbr; its mod.io description, user-pasted
  2026-10-14) says the same: its shaders can't be installed by the mod; the player copies its
  `Shader files/base/content/rendering/programs` over the game's `base/content/rendering/programs`, deletes
  `shader_cache` and restarts; restore = Steam "Verify integrity of game files". The decisive in-game check is
  still open: `mods/square_shader_override_probe` (magenta compose.fs, plans/square_photo_quality_probe/TESTING.md
  T12, never run). Base `rendering/` is loose files in the install (not in a zip), so a manual copy works.
- **Compiling**: GLSL 1.50 with `GL_GOOGLE_include_directive`, compiled by glslang to SPIR-V for Vulkan (MoltenVK
  on macOS) at load; `.spv` files plus `cache.lua` (each program's sources with their write times) in
  `shader_cache/`. Executable strings: "Initial shader generation in progress", "Invalid cache for: {}, will be
  recreated" (a changed source's write time invalidates its entry, inferred), "Invalid parse for shader",
  "Invalid link for program '{}'", "Could not read include file", "Shader reload failed!" (AltGr+R in debug
  mode). What a failed compile does at startup (fallback, black pass or crash) is unknown.
- **Mod Hub upload and consoles (executable strings, inferred)**: the Hub's validator knows `.fs .glsl .glsli .vs
  .shader` and reports "File extension is only allowed on PC/Mac/Linux (mod will not be available on Consoles)":
  the upload goes through, the result carries separate PC and console levels and cooked paths
  (`levelPc`/`levelConsole`, `cookedPcPath`/`cookedConsolePath`), and mod.io files carry per-platform approval
  (`/files/{file-id}/platforms`); wiki `publishing.md`: only a mod that meets the console rules gets a console
  version. So a shader file in a mod makes the whole mod PC-only automatically; there is no modinfo platform
  field to set. `.gs` is not in that list. No official or subscribed mod ships a shader (`find` over
  `.cache/game/mods`, `.cache/subscribed`, the mod.io install folder: none).
- **Data channel into shaders**: post-processing passes see only their own uniform blocks (`descriptors/*.desc.lua`):
  compose = frame, bloom blur, exposure / tone-map values (`Blur`, binding 4); `ssr_apply` = colour, normals,
  depth, a blurred mip chain, `Ssao` (4), `Light` (6, has `latitude`), shadow (8), `View` (10). The live
  atmosphere fields (`Atmosphere`, binding 5) reach only material, fog, sky and cloud shaders. REP passes its own
  data that way (description): decimals of `cloudBase` / `cloudTop`, the lowest bits of `cloudScattering`, and
  `dayOfYear`. **Photo Mode writes those same fields live** (day / season, Low clouds weather 500 / 1800 m, every
  look switch resets them to the file's values and carries the live values back), so Photo Mode can overwrite
  REP's encoded data: expect REP's look to break while Photo Mode changes day or clouds (inferred, not tested).
- The DoF probe (`mods/square_photo_dof_probe`, plans/square_photo_dof_probe) uses another channel that neither
  REP nor Photo Mode touches: `light.latitude + 2 pi * mode` in an env file (only the sky's star rotation reads
  latitude in the shaders, through a rotation; the CPU sun path is assumed periodic too, unverified).

## Water: one block for sea and rivers, no flow speed or direction (from the game files 2026-10-14, inferred)

- An env file has one `water` block and the base has one water material (`rendering/programs/water*.prog.lua`),
  so sea, lakes and rivers share its values (inferred; rivers on a map were not compared in game).
- `shaders/mat/fs/water_normals.fs`: the normal map is sampled six times, each scrolled by the clock in a fixed
  direction 60 degrees apart (`rotate(vec2(u_view.time, 0), PI_THIRD * i)`): no flow direction and no speed field,
  rivers don't flow downstream. Strength = `normalScale * 0.5 * log2((depth + 5) / 4)` (about 0.16 at 0 m, 0.5 at
  3 m, 1.3 at 20 m deep), so shallow rivers show far weaker waves than the sea at the same `normalScale`; the
  normal is normalised, so large values tilt it towards flat-out chaos and (`water.fs`, `normalFactor`) pull the
  colour towards the shallow end of `depthColorTex`. `preferLowFreq` is most likely the shader's `invertWeights`
  (low-frequency samples weighted up).
- `roughness` adds `2 x roughness` to the reflection's mip level (blurrier reflections); `extinctionCoeff` sets
  how fast light fades through the water (0 = clear, 1 = opaque); `particleDensity` is in the shader's uniform
  block but no shader reads it; `waveFoamTex` drives the animated shoreline foam (`water_waves.fs`, 20 s cycle).
  Only one water normal map ships (`climates/shared/water_normal.dds`); a mod could ship its own (DDS) for
  choppier water.
- Photo Mode round 11 "Wild water": `normalScale = 6` (a river at 1 m depth gets ~1.75, a stormy sea's look),
  roughness 0.6, foam, extinction x8. To be seen in game (TESTING.md K14).

## Haze can't be near + clear middle + far: it only grows with distance (from the game files 2026-10-14)

- Haze ("aerial perspective") is integrated along the view ray from the camera to the pixel
  (`shaders/atmosphere/common.glsl` `integrateScatteredLuminance`, baked per frame into `aerialPerspectiveLUT` by
  `aerial_perspective_LUT.fs`, applied in `shaders/util/fog.fs` `applyFog`): transmittance only falls and scattered
  light only grows with distance. There is no fog start distance, near fade or band: whatever haze lies in front
  of the focus also lies in front of everything behind it. Density follows altitude above sea level
  (`exp(mieDensityExpScale * height)`, `rayleighDensityExpScale`), not height above the terrain, so there is no
  ground-fog layer to sit in.
- `fogScaleLow` / `fogScaleHigh` (env `atmosphere`, file only) multiply the horizontal path length: Low for a camera
  up to 100 m above sea level (game z), High from 2.1 km up, in between mixed by `fz^2` with
  `fz = 1 - clamp((camera z in km - 0.1) / 2)` (`cameraHeight` there subtracts `bottomRadius + heightOffset + 0.1`
  from the camera's planet-space height, so `heightOffset` cancels out); base 3-4.4. With `mirrorSky = true` (all
  four base climates) the factor is scaled by `(1 - |dz| / distance)^2`: full for a level ray, less looking down.
  (Corrected after a re-read of the shader: this line said "Low for a camera near `heightOffset` (0.5 km)".) A larger Low value = more haze for low shots, still growing with distance.
- `getFogFactor` fades geometry into the sky colour over the last 1000 m before the far plane (draw distance).
- The only near haze is a cloud: with the camera between `cloudBase` and `cloudTop` (both live-settable) the cloud
  march runs from the camera (`applyFog` case 2) and everything is veiled; above the layer, the clouds sit between
  camera and ground. Neither leaves a clear middle.
- So haze can give a "soft background" (more Mie / `fogScaleLow` in a look file: far detail fades, near stays
  crisp), which reads a little like a long lens focused near; a real in-focus band needs a shader (the DoF probe).
  Photo Mode's "Soft background" haze look does this (plans/square_photo_mode/LOOKS.md "Round 12"; round 11's
  extreme version turned the whole frame into murk: next section).
- The scattering is single only (no multiple-scattering term in `integrateScatteredLuminance`), so haze far away
  tends to `sun x (mie scattering x phase + Rayleigh x phase) / extinction`: bright towards the sun (Cornette-Shanks
  phase, `miePhaseG`), dim sideways and away (g 0.8: 0.008 sideways vs 4.1 at the sun), and mie absorption only
  greys it.

## Haze: the sky sees the whole mie column, the land the fog-scaled one; dense, tall aerosol kills the sky (game files + user screenshots 2026-10-14)

- **Seen in game** (session `2026-10-14_0229_sqrl-sqst`, Dry map, user screenshots, the live cloud cover 0.7-0.78):
  Photo Mode's round 11 Soft background (mie scattering 0.25 with `mieScaleHeight` 2.0 km, no absorption, phase g
  0.45, fogScaleLow 25) made everything beyond ~50 m "a heavy grey-brown murk" and the sky "a dull grey-mauve
  overcast"; the climate's sky with less mie (Crisp & clear) at the same place showed a pink sky and far cliffs.
- **Why, from the shaders** (`rendering/programs/shaders/atmosphere/`): the sky (`sky_view_LUT.fs`) and the sun's
  transmittance (`transmittance_LUT.fs`) integrate the mie density through the whole atmosphere without the fog
  factor (`integrateScatteredLuminance(..., applyFogFactor = false)`), while the land's aerial perspective
  (`aerial_perspective_LUT.fs`, `true`) multiplies its step length by `fogScaleLow` / `High`. Mie density is
  `exp(mieDensityExpScale x (altitude above sea level + heightOffset))` (heightOffset 0.5 km in all four climates;
  `mieDensityExpScale` is set by the engine from `mieScaleHeight`, inferred `-1 / mieScaleHeight`). So a large mie
  with a tall scale height fills the sky's column (zenith optical depth ~0.23, ~16 along the horizon in that look:
  a grey sky) and dims and reddens the sunlight that lights the veil (~20 % left at a 10-degree sun), and the veil
  is then darker than the land. The same veil from a mie packed low (small `mieScaleHeight`) times a large
  `fogScaleLow` leaves the sky's column thin. `mieScatteringScale` is capped at 1 (wiki), and the 0.5 km offset
  divides the sea-level density by `exp(0.5 / mieScaleHeight)`, which limits how low the layer can go (0.4 km:
  29 % at sea level).
- **Brightness away from the sun** is the mie phase alone (single scattering, no absorption: the far veil tends to
  sun x transmittance x phase): Cornette-Shanks g 0.45 gives 0.033 per sr sideways vs 0.080 isotropic; g 0.1 is
  near-isotropic (0.058 sideways, 0.088 away, 0.16 towards the sun). Below the cloud base `util/fog.fs`
  multiplies the veil by `1 - 0.75 x cloudCoverage` (`getCloudCoverageFactor`), as the sky.
- The base env files also carry `mieScatteringScaleOvercast`, `mieAbsorptionScaleOvercast` and
  `miePhaseGOvercast` (0.5 in all four), not in the wiki: most likely blended in with the cloud cover (inferred;
  the base game itself gets hazier under clouds: Dry 0.014 -> 0.2).
- Photo Mode round 12 retuned it (LOOKS.md "Round 12": 0.27 with 0.4 km, g 0.1; model 44 % veil at 500 m vs 76 %,
  the sky 20 degrees up blue/red 3.2 vs 1.6, climate 4.6). In game: TESTING.md K23.

## No soft foreground from haze: transmittance only falls along a ray (game files 2026-10-14)

- `integrateScatteredLuminance` multiplies the transmittance from the camera outward and only adds scattered
  light, so haze in front of a near object is in front of everything behind it on that ray; foreground rays at the
  bottom of a downward view are shorter and steeper (less fog with `mirrorSky`). No env field gives a near-only
  veil. A density rising with height needs a negative `mieScaleHeight` (outside the wiki's 0-100, never used by a
  base or campaign file; the engine's conversion and any clamp are not in the files): it would grow up to the
  atmosphere's top (100 km), overflowing or filling the sky, and still veil the ground below as much as the air
  near the camera. Not tried in game. A cloud layer at the camera's height (live `cloudBase` / `cloudTop`) also
  veils everything behind it. A soft foreground needs a depth of field (shader).

## Rain shows from cloud cover 0.8, full at 1.0, only below the cloud base (game files 2026-10-14, inferred)

- `rendering/programs/shaders/atmosphere/rain.fs`: a rain streak's alpha is `rain x smoothstep(1 -
  smoothstep(0.8, 1.0, |cloudCoverage|), 1.0, noise) x 0.8`: below 0.8 nothing passes, at 0.9 about half the
  streaks, at 1.0 all; streaks above `cloudBase` are discarded (`vpos.z > u_atmosphere.cloudBase`). So the live
  cloud cover alone makes rain (Photo Mode's Storm preset 1.0, the Clouds slider from 80 %), and a cloud deck
  lowered with the live `cloudBase` (Low clouds, the Cloud height slider) keeps rain under it. Not seen in game
  (Photo Mode TESTING.md K6, RS6).
- No snow, wetness, wind or lightning field exists: no shader reads one (`rg -i 'snow|wet|wind|lightning'` over
  `rendering/programs/shaders` finds only the town windows' light code), and `dayOfYear` is read by no shader at all
  (it reaches only the CPU's sun path), so a season change moves the sun, not foliage or snow (inferred; TESTING.md
  K9 is the in-game check).

## Window and lamp glow follows `light.globalEmissiveScale`; `cloudScattering` is the clouds' density (game files 2026-10-14)

- `light.globalEmissiveScale` (1.5 in all four base climates, file only) multiplies the lit town windows
  (`mat/fs/normal/physical.fs:455`, `finalColor x lightPower x globalEmissiveScale`, the window light's time of
  day from `getWindowLightPower`) and every emissive material (`mat/fs/normal/emissive.fs:45`). An env file can
  brighten a night's windows and lamps without touching the sky (Photo Mode round 16: Moonlit night x2, Neon dusk
  x2.5). `globalLightSourceScale` is in the env files but no shader reads it (CPU light sources, inferred).
- The live `cloudScattering` (engine default 0.005; no base env file sets it) is the cloud march's scattering
  coefficient: `atmosphere/cloud.h.glsl` `extinctionCoeff = scatteringCoeff + absorptionCoeff`, times the noise
  density per step, so a larger value makes thicker, more opaque clouds (inferred; how it reads in game is Photo
  Mode TESTING.md RS7). `cloudAbsorption`, `cloudColor`, `cloudSpeed` and `cloudPhase` are in the shaders'
  `Atmosphere` block too (`pbr/atmosphere.h.glsl`) but not in `Environment.AthmostphereParams` (not live); the wiki
  names `cloudSpeed` / `cloudPhase` as env fields, no base file sets them.

## The base game's other environments: Legacy, Test, model editor; the campaign uses the base climates (game files 2026-10-14)

- Every base climate folder has a `<c>_old.env.lua` (`name = "Dry (Legacy)"` etc., plain text, `isToolEnvironment =
  true`): the older atmosphere. Against today's climate: `heightOffset` 10 km (0.5), Rayleigh with a 100 km scale
  height and 0.33-0.6 x the scattering, mie 0.027-0.107 with a 1.7-2.4 km scale height (which the 10 km offset
  thins to ~1 % near the ground), `fogScaleLow` 10-12.5 (3-4.4), an ozone `absorptionCoeff` that absorbs red as
  well as green ({1, 0.75, 0.15} on Dry; today's {0.33, 0.94, 0.04}) at 1.5-5 x the scale, `hdrExposureDay` 1.72, `refBrightness` 1.1-1.3 and a single-number `hdrContrastDay` (1.31-1.36);
  `temperate_old` also sets `skyRotation`. Water and latitude as today's. Photo Mode's Legacy look switches to them
  (ResName `::/climates/<c>/<c>_old.env`, inferred from the climates' own; round 16, TESTING.md RS8).
- `subarctic/subarctic2.env.lua` "(Test)": temperate's look with subarctic's latitude and a different tone map
  (`hdrTarget` 0, `hdrMax` 16): a test file. `model_editor/environments/*.env.lua`: studio lighting for the model
  editor (exposure 1.4-1.72, `refBrightness` 0.65-0.7, a fixed `sunRotation`, `useSkyBoxOverwrite` in the
  substance one), legacy-style atmospheres.
- The campaign's env files (`urbangames_campaign_mission_01..08`, `content/clima*/**/*.env.lua`) are copies of the
  base climates with absolute texture paths; only mission 7 differs (water `extinctionCoeff` 0.015, clearer) and
  missions 1 / 8 (shoreline foam off / on). No mission has a special atmosphere.
- Evidence: a scratch diff of every non-climate env file against the closest base climate (lupa, 2026-10-14).
