# Findings: Publishing (Mod Hub, mod.io)

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## Mod Hub uploads and the mod.io gallery (2026-10-10)

- A Hub update uploads every slide in `_metadata/`, whatever its name: `N.png` and `N-<hash>.png` both show up
  on the upload screen and on mod.io.
- With slides named `N.png`, a Hub update left the mod.io gallery wrong: it added new numbers next to old ones
  (Problem Radar rev 2 showed the settings slide twice) and the stored files were not byte-identical to the local
  slides. `make modio ARGS=--apply` fixed it by replacing the gallery as `N-<hash>.png` (`tools/modio_sync.py`).
- With local slides named `N-<hash>.png`, the name `make modio` uploads them under, a Hub update left the gallery
  exactly as it was: Blank Slate rev 3 (renamed slides, Hub upload) then gave "in sync" in
  `make modio ARGS='--diff --verify'`, which downloads mod.io's originals and compares bytes. So `make shots` now
  writes `N-<hash>.png` (first 8 hex digits of the sha256 of the file), and `modio_sync.py` reads both forms.
- The same Hub upload sent the new `description.html` (rev 3 changelog entry) to mod.io. Earlier Hub updates
  seemed to leave the description old; the cause is unknown (maybe a description edited while the game was
  running, or mod.io's scan delay). Check with `make modio ARGS=--diff` after an upload.
- **A description edited while the game runs is picked up; the Hub upload still left it old (2026-10-21, inferred).**
  Line Manager Plus rev 13: `description.html` (new Changelog entry) and `mod.json` were edited at 07:03:35 UTC in a
  game started at 06:59; the game logged `Staging Mod at .../square_line_manager_plus/ has modified files` that same
  second, and the Hub upload at 07:04:06 shipped rev 13, yet mod.io kept the rev 12 description (user report). So
  "edited while the game was running" is not the cause. Every Hub upload in the archive (17 from 2026-10-18 to
  2026-10-21, e.g. `2026-10-20_1947_sqot-sqfn`, `2026-10-21_0659_sqot-sqrl` line ~2104) logs one
  `[Error][Http] Non 200-204 response received: {"error":{"code":500,...,"message":"Unexpected server error..."}}`
  about 3 s after `Updating mod <id> on backend mod.io`, right after the modfile uploads start, then
  `changed status: Undefined error: 0`, and the modfile and gallery still go through. Likely (not proven: the log
  doesn't name the request) the 500 is the Hub's profile edit (name, summary, description), which it neither retries
  nor reports. Until that's settled: after every Hub upload, run `make modio MOD=mods/<id> ARGS='--only text --diff'`
  and `--apply` when the description differs.
- The Hub's gallery strip sorts `_metadata` slides by file name as text: with 22 slides it showed 1, 10, 11 … 19,
  2, 20 (Roundabouts, screenshot 2026-10-10). `make shots` now zero-pads the number when a mod has 10 or more
  slides (`01-<hash>.png`), and `make modio` uploads under those same names.
- **A Hub update leaves mod.io's gallery out of order (2026-10-14).** After the Smart Lanes rev 6 Hub upload (10 slides
  `01-<hash>.png` … `10-<hash>.png`, a new slide 3 inserted so slides 3-9 moved up one number, same hashes) mod.io
  listed `01-b792101e.1.png, 10-bea91124.png, 02-c1b9a283.1.png, 03-…, 09-…` (`make modio ARGS=--diff`): every slide
  there (the `.1` copies are names that existed before: the Hub re-uploads every slide), but slide 10 second, as if
  the numbers were sorted as text without the zero ("1", "10", "2"). Roundabouts and Line Manager Plus showed the
  same order: exactly the three mods with 10 slides (two-digit names); every mod with 1-8 slides stayed in order
  through its Hub uploads. The mod.io page shows that order. `make modio MOD=mods/<id> ARGS='--apply --only gallery'`
  replaced Smart Lanes' gallery in slide order (`--diff`: in sync). Decision: at most 9 slides per mod (single-digit
  names, `tools/render_shots.py` MAX_SLIDES). Inferred, not checked: that 9 single-digit slides stay in order (no
  9-slide Hub upload seen yet), and whether the Hub sorts by unpadded number.
- **The Hub uploads the slide list it read at game start (2026-10-14).** Roundabouts' slides were re-rendered (10 -> 9,
  new names) at 05:27 UTC in a game started at 05:02; its Hub upload at 05:29 logged "Uploading gallery images" then
  `Could not finish mod gallery upload: File not found` (session started 2026-10-14 05:02, `stdout.txt` line ~10010),
  and mod.io kept the old 10 slides. Restart the game after `make shots` and before a Hub upload (or fix the
  gallery with `make modio MOD=mods/<id> ARGS='--apply --only gallery'`, which needs no game).
- **Too many gallery images fail the Hub upload.** Roundabouts with 22 slides, then 19 (plus `0.png`), failed in the
  Hub with "Uploading gallery images: Unknown ApiError error (Error Code: 13003)", which mod.io's error list
  (docs.mod.io/restapi/errors) names `FILE_TOO_MANY`. The 9-slide gallery uploaded fine. The limit isn't documented;
  it may count the old gallery images on mod.io too (9 there at the time). Cut to 10, the Hub upload worked
  (2026-10-10). `make shots` refused more than 10 slides per mod (9 since 2026-10-14, entry above).

## mod.io description HTML: blockquote, images, links (2026-10-13, mod.io page, frontend code, a live upload and the in-game Mod Hub)

Source: the rendered Pay Your Tolls page (`mod.io/g/transportfever3/m/pay-your-tolls`, headless Chrome `--dump-dom`)
and mod.io's own JS/CSS bundles.

- **`<blockquote>` works on mod.io.** Pay Your Tolls opens with `<blockquote><p><strong><em>"…"</em></strong></p></blockquote>`;
  mod.io styles it as a box with a dark background, a 4 px left border and padding (`.mod-content blockquote`).
  Whether the in-game Mod Hub renders it is untested: the quote must read fine as a plain paragraph.
- **Images work on mod.io:** `<img src="…" width="200">`, wrapped in `<a href>` to make a clickable tile. Pay Your
  Tolls' "MORE FROM" section links each of its other mods with one of that mod's own mod.io images, so nothing
  new is uploaded. mod.io's CDN path is `https://image.modcdn.io/mods/<md5(modioId)[:4]>/<modioId>/<filename>`
  (checked on 3 of their mods and 4 of ours), with resized copies at
  `https://thumb.modcdn.io/mods/<…>/<modioId>/crop_640x360/<filename>` (also `crop_320x180`; `crop_480x270` does not exist).
  The filename is the mod.io one (`branding/modio_state.json` `logo.remote` / `images[].remote`, e.g. `0.14.png`), which
  changes when the logo is replaced, so generate such links from that file rather than writing them by hand.
- **Image CSS on mod.io:** only `display:inline-block` plus the usual `max-width:100%; height:auto`, with no rounding or
  fixed size. A `width` attribute sets the size; a percentage works and scales with the page. Images sit inline, so the
  spaces between tiles take room: four tiles per row need `width="24%"` (at 25% the fourth wraps). Wrapped rows touch (no vertical gap); `vspace`/`hspace` are not in DOMPurify's allowlist (checked in the bundle), and `style` is stripped on save (below), so there is no way to add one; `border`, `align`, `cellpadding`/`cellspacing` are allowed.
- **Sanitizer:** the page cleans the description with DOMPurify's defaults plus `target`, `frameborder`,
  `allowfullscreen` and `<iframe>`. DOMPurify keeps `style`, but **mod.io's server strips `style` on save
  (verified 2026-10-13)**: Stress Test's description went up via `make modio --only text` with
  `<img … width="200" style="margin-bottom:8px">` tiles; the live page has `<img … width="200">` and no gap. `width`,
  `alt`, `<a href>` and a link inside `<h4>` survived. So no inline CSS (rounded corners, margins); wrapped tile rows touch. The page also turns a bare YouTube link into
  an embedded player and plain URLs into links. `<table>` gets styled rows (`.mod-content table`).
- The swagger only says the description "allows HTML" (`api.mod.io/v1/swagger`); no tag list is published.
- **In the game's Mod Hub tab (verified 2026-10-13, user screenshot of Stress Test after `make modio --only text`):** the
  Hub showed the new description at once (it reads mod.io's profile, "Date Updated" the same day). `<img>` is dropped;
  `<a href="U">text</a>` shows as `text (U)`, also inside `<h4>`; a link whose only content is an image shows as the
  bare `U`. So linked logo tiles turn into rows of raw URLs in game. `<h4>`, `<strong>`, `<ul>` render as in
  "Mod description rendering in game" (scripting.md).

## Description length: 50,000 characters (2026-10-16, Mod Hub upload)

- **mod.io rejects a description over 50,000 characters.** The Mod Hub upload of Smart Lanes rev 8 failed with mod.io
  error 13009: `The "description" may not be greater than 50000 characters.` Its `description.html` was 57,661 characters
  (57,681 bytes); trimmed to under 15,000, see the mod's Revision 8. The swagger's `description.maxLength` of 150,000
  (`api.mod.io/v1/swagger`) is not what the upload enforces. Characters, not bytes, are counted (assumed: mod.io's
  validator works on the string; the failing file was mostly ASCII, so both counts were over).
- `make validate` errors above 50,000 characters and warns above 40,000 (`tools/validate_mod.py` `check_description`).

## Upload validator runs script chunks without `api.engine` (2026-10-20, Mod Hub upload)

- **The Hub's upload validator executes a GUI script's top-level chunk in a state where `api.engine` is nil.**
  Industry Production Label rev 8 failed the upload with "Lua Content ERROR … Failed to parse Lua … attempt to
  index field 'engine' (a nil value)" at `production_label_entry.script.tl:28`, a module-level
  `pcall(api.engine.config.getModParams)`: the field access is evaluated before `pcall` runs. The same file loaded
  fine in game. Fix: put every load-time api read inside the protected function
  (`pcall(function() return api.engine.config.getModParams() end)`) or read lazily at mount. Related: the
  validator also checks `<modId>::` paths (roads.md, 2026-10-08). `make validate` doesn't catch this.

## Server-side validation rejects `api.util.saveAppConfig` (2026-10-20, mod.io / Urban Games review)

- **Uploads that call `api.util.saveAppConfig()` are rejected after upload.** Line Manager Plus and Photo Mode
  updates "did not pass the server sided validation as it uses an api function that is not intended to be used by
  mods. Instead of using api.util.saveAppConfig(), please use api.gui.game.setGuiSaveData("modId", { x = 1 }) to
  store data." (message to the user, 2026-10-20). Both wrote mod prefs into `AppConfig.mainMenuState[key]` (the
  game's settings.lua) with getAppConfig -> setAppConfig -> saveAppConfig; Better Minimap and Problem Radar did the
  same and were changed with them before their next upload.
- **Store mod data with `api.gui.game.setGuiSaveData(modId, table)`** and read it with `getGuiSaveData(modId)`
  (`api/tealdef/api/gui.d.tl:773-781`). It is GUI data of the savegame: kept when the player saves, empty in a
  new game, so prefs are per save, not shared by every game. The call replaces the modId's whole table: one writer
  merges every part (Photo Mode: views, markers, setups in one table). Removing the mod leaves the save loadable
  without a warning (Photo Mode TESTING P11).
- **No official doc states the rule** (searched 2026-10-20: wiki mirror, tealdef, base content, official mods). The
  only hints: `getGuiSaveData` / `setGuiSaveData` take a `modId` ("the mod to get the user data for",
  `gui.d.tl:773-781`), i.e. built for per-mod data; `util.d.tl` documents `saveAppConfig` just as "Saves the game
  settings"; `AppConfig.mainMenuState` is "filled by the UI scripts" (`type.d.tl:2886`), meaning the base menu. The
  base game itself uses only `setGuiSaveData("")` (its HUD filter, `layer_hud_filter.tl`). The review message is the
  only source; the likely reason (inferred) is that settings.lua is shared by every game and outlives the mod.
- `api.util.setAppConfig` (Photo Mode's graphics switch) was not named in the rejection. Settings written to
  `mainMenuState` without `saveAppConfig` reach settings.lua only when the game itself saves its settings.
- `make validate` errors on `saveAppConfig` anywhere in a mod's `.lua` / `.tl` (comments included) and warns on a
  `mainMenuState` write.
