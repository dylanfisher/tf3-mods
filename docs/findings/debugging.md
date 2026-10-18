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
102fbe0cc is the stylesheet rule count ("Load crash above ~200 mod stylesheet rules", scripting.md): count CSS (`make css-rules MODS=...`)
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

## A script loop that never ends: "Possible hang detected", no Lua error (2026-10-13, game log)

Session `2026-10-13_1848_sqot`: Organic Towns' head-start planning for one town (Henley-on-Thames, round 2, right
after its `SNAPSHOT` line) never returned. The log then shows only `WARNING ... Thread did not respond to ping.
Possible hang detected!` every ~4 s for about a minute, after which the game quit. The crash_dump `error.json` has
`"message": "Possible hang detected"` with no file, function or line. There is no Lua error, no stack and no
`[SQOT]` line about it. So an endless or very long loop in a mod script (game script or GUI script) shows up only as the game's watchdog firing:
find it from the last mod log line before the warnings. Rule for our mods: CLAUDE.md "TF3-specific facts" (cap
every loop and graph walk).

## Money from the console: no cheat command, book a journal entry (2026-10-13, research; console use untested)

No built-in money cheat or console command was found (wiki `modding/tools/ingame.md` "Console" lists only `\help`,
`\clear`, `\stdout`, `\timestamp`, `\scrlk`, `\history`; nothing in `api/tealdef` or the base files). The console
runs Lua, so book money the way our mods do (`square_full_refund` `refund.script.tl`, `square_stress_test`
`stress_runtime.tl` `rt.book`; `makeJournalBookAssetCmd`, `api/tealdef/api/cmd.d.tl:747`). From a mod GUI script this
is verified: Stress Test's keep-balance top-up took the balance to 204M (`findings/lines-vehicles.md` "Stress Test
probes"). Typing it into the console prompt itself is not yet tried.

```lua
local e = api.type.JournalEntry.new()
e.amount = 1000000000   -- negative to take money; -math.floor(api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())) zeroes it
e.time = -1
e.category.type = api.type.JournalEntry.Type.OTHER
api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), e, api.type.Vec3f.new(0, 0, 0)))
```

Keep one booking at or below 1,000,000,000 (Stress Test's `MAX_BOOKING`, a guard against a possible 32-bit amount;
the limit itself is untested). No "unlimited money" / no-costs setting was found.

## Spawning an animal from the console: `makeAnimalSpawnAtCmd` works (2026-10-14, game log)

Typed into the in-game console prompt (live `stdout.txt` 2026-10-14 08:01-08:02Z, archived with the next session):

```lua
local c = api.gui.camera.getCameraData(); api.cmd.sendCommand(api.cmd.makeAnimalSpawnAtCmd("::/animal/cougar/cougar.mdl", api.type.Vec2f.new(c.x, c.y)), function(d, ok) print("spawn ok=", ok, "entity=", d.resultEntity) end)
```

- Four spawns (camera centre and `api.gui.mouse.getTerrainPosition()`): each printed `spawn ok= true entity= <id>`
  (113819, 121588, 71258, 133206). The `::/animal/<name>/<name>.mdl` form (as `livestock_farm.script.lua` names
  animals) is accepted; the bare `animal/...` form is untried. `lookAt` is optional.
- The callback runs and `d.resultEntity` holds the new animal's entity id. `print` from the console lands in
  `stdout.txt` without the usual timestamp prefix.
- The console proves the first one-liners work: a multi-statement line (`local ...; api.cmd.sendCommand(...)`) runs.
- Unrelated noise in the same session: a `ProposalData error: Collision` road proposal (node 51651) also logged at
  07:54Z, before any console input.
- **A spawned animal falls over and vanishes within seconds when the spot is unsuitable** (seen by the player
  2026-10-14). That is the "Dying" movement type (`eventName = "die"`, `despawnAtEnd = true`). Each wild animal's
  `metadata.animal.suitableAreas` scores the spot (wiki `modding/environment/animals.md` "Suitable Areas": a
  negative score makes it run, failing that it dies). Cougar (`dry.clima`): `civilisation`, `water`, `shore`,
  `ship` = -1000, `forest` -4, slope > 0.3, noise > 60, height > 400 penalised, `bias` 5. So a spawn in front of the
  camera near roads, buildings, water or traffic noise dies at once. "Dying" also has `playRandomly = true`, so wild
  animals can die at random anyway.
- `cow/cow.mdl` has no `animal` metadata (a livestock-farm prop), yet the spawn command still reported `ok=true`.
  Wild animal models with `suitableAreas`: `bird_eagle`, `bird_crane`, `bird_gull`, `wildlife_fox`, `wildlife_bear`,
  `wildlife_deer`, `wolf`, `cougar`, `draft_horse`, `fish_salmon`, `cr_fish/cr_fish_01..04`.
- Still open: whether a spawned animal persists in the save and despawns, and how to remove one (no despawn command in
  `api/tealdef/api/cmd.d.tl`).
