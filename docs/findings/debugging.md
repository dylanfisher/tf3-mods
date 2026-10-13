# Findings: Debugging and the game install

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## Paths in the user's install (macOS Steam)

- Userdata: `~/Library/Application Support/Steam/userdata/<id>/3493540/local/`. `crash_dump/` holds `stdout.txt`
  (the live log, rewritten at every start; archived by `tools/game_logs.py` into `.cache/logs/`), and per error
  `<uuid>_N.txt` (log copy), `<uuid>_M.json` (errorInfo, active mods, modParams) and `.dmp` minidumps.
- In-game screenshots land in `screenshots/` there as `<YYYY-MM-DD_HH-MM-SS>_img_<n>.png`, also from
  `api.gui.camera.takeScreenshot` (verified: the game logs `Screenshot: wrote <path>`, session
  `2026-10-12_0504_sqot-dev-sqperf-crash`; `takeScreenshot(1)` gave the full 2560x1440 viewport). Read them
  directly instead of asking the user to paste; label them with log lines such as `[SQOT_DEV] SHOT n= town= view=`.
- `.cache/game` has text files only. Binary assets (icons, textures) are in plain zips per folder under
  `~/Library/Application Support/Steam/steamapps/common/Transport Fever 3/base/content/` (e.g.
  `infrastructure/street.zip`, `gui.zip`); read them with `zipfile` / `unzip`. Vanilla display text is the gettext
  catalog `base/strings/<lang>/LC_MESSAGES/base.mo` (Python `gettext.GNUTranslations(f)._catalog`);
  `content/locale/*.lang.lua` holds only font settings.

## Native crash stacks with lldb (2026-10-07)

`lldb --batch -o "target create --core '<file>.dmp'" -o "bt 40"` reads the macOS breakpad dump and symbolizes
system frames (game frames are unnamed). For an uncaught C++ exception, `frame select 7` (the `__cxa_throw` frame)
+ `register read x20` shows the exception typeinfo. The python `minidump` package misparses these dumps. A crash
with an empty message has no Lua trace. The recurring load crash with frames 8/10/11 = 100016a50 / 10003d16c /
102fbe0cc is the stylesheet rule count ("Load crash above ~200 mod stylesheet rules", scripting.md): count CSS
rules before bisecting mods. Before blaming a mod change, check stdout for `runtimeRevision` bumps during the load
(another session writing into a linked mod) and match crash-time params via the json's `gameInfo.modParams`.

## Vulkan drivers and profiling on macOS (2026-10-10, build 40420)

The install has two Vulkan ICDs: `MoltenVK_icd.json` (default; the encrypted `run.sh` launcher sets
`VK_ICD_FILENAMES` and `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1`) and `libkosmickrisp_icd.json`. KosmicKrisp loads
but renders terrain as black patches: not usable. macOS Steam launch options reject `VAR=value %command%` ("OS Error
260"); use a wrapper as the first word (`tools/tf3_kosmickrisp.sh` sets `VK_DRIVER_FILES` and `exec "$@"`).
Profiling: `sample <pid>` works on the live game (stripped binary, thread names only). Port terminal placement is
~4-5 s main-thread `sleep_for` waiting on Main Pool + RenderDataManager workers (engine, vanilla); MoltenVK
`MVKDevice::removeBuffer` costs ~9-12% of the main thread constantly.

## Reloading a save replays the simulation deterministically (2026-10-12)

Two loads of the same save (desert save, session `2026-10-12_2343_top-up-563524`, probe `square_sim_tuner_probe`,
both at `simPersonDestinationRecomputationProbability` 0.2, 4x, no input) gave identical per-10-day counts of
re-picked destinations over 400 sampled persons (3,3,7,5,2,2,3,4,4 in both), as did a third load in an earlier
session. Load-to-load A/B of a load-time setting is therefore a fair comparison over the same in-game days, as long
as nothing is clicked or built. Changing the setting (1.0) changed the counts from the first window on.
