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
- The Hub's gallery strip sorts `_metadata` slides by file name as text: with 22 slides it showed 1, 10, 11 … 19,
  2, 20 (Roundabouts, screenshot 2026-10-10). `make shots` now zero-pads the number when a mod has 10 or more
  slides (`01-<hash>.png`), and `make modio` uploads under those same names.
- **Too many gallery images fail the Hub upload.** Roundabouts with 22 slides, then 19 (plus `0.png`), failed in the
  Hub with "Uploading gallery images: Unknown ApiError error (Error Code: 13003)", which mod.io's error list
  (docs.mod.io/restapi/errors) names `FILE_TOO_MANY`. The 9-slide gallery uploaded fine. The limit isn't documented;
  it may count the old gallery images on mod.io too (9 there at the time). Cut to 10, the Hub upload worked
  (2026-10-10). `make shots` now refuses more than 10 slides per mod.
