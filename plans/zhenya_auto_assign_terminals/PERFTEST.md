# Perf test: Auto Assign Terminals, original vs optimized

DEV mod: `mods/square_aat_perftest` ("DEV AAT Perf Test", **not for upload**). It is Zhenya_'s Auto Assign Terminals
(rev 19) with two implementations behind one setting, **Implementation (perf test)**:

- **Original**: the author's code, unchanged apart from timers (`content/base/`, `content/gui/base_eow.lua`).
- **Optimized**: the same code with the fixes from `AUDIT.md` (`content/opt/`, `content/gui/opt_eow.lua`).

Both log the same `[AATPERF]` lines to `<userdata>/crash_dump/stdout.txt`, one per 30 s from each Lua state.
`perf_report.py` compares the two.

## What gets measured

| Name | Side | What it is |
|---|---|---|
| `sweep` | game script | One pass over the lines. **max ms** is the stutter: the longest single tick the mod held the simulation |
| `update` | game script | Every call into the script, including the quick early returns |
| `lineCargo`, `vehiclesRead` | game script | Reading every vehicle of every line (audit #3) |
| `stateGet`, `stateSet` | game script | Copying the saved state in and out (audit #2) |
| `assignStop`, `path`, `pathPrint`, `networkComponentReads` | game script | Actual terminal choice and path searches (audit #4) |
| `eventBuild` | game script | Work done on every build of anything |
| `stateBytes`, `signatureBytes` | game script | Size of the saved state and of its signature strings |
| `readState` | GUI | Copying the state into the GUI (audit #1) |
| `gui*` | GUI | Each card or button's poll; `guiGameBarWidget` is the always-on game-bar widget |
| `frames` | GUI | Frames counted, so the report can show **mod GUI ms per frame** |

Timers use the engine's microsecond wall clock (`api.type.Clock`). Both modes carry the same timers, so their
small overhead cancels out.

## Running it

Do this on a **copy of your biggest save**, for two reasons. This copy keeps its own settings, separate from the
original mod, so stops you set to manual there are automatic here. And if you answer "Automatic" to its first-run
question, it may reassign terminals.

1. In game: load your biggest save, **Save As** `aat-perftest`, then quit to the main menu. Never add or remove
   staging mods while a save is loaded.
2. `make link` (links every mod in `mods/`, this one included).
3. Load `aat-perftest`. In the mod list of the load dialog:
   - **disable** "Auto Assign Terminals" (the subscribed one; the two are marked incompatible),
   - **enable** "DEV AAT Perf Test", and in its settings set **Implementation = Original**. Leave every other setting as
     in the original mod and leave **Debug log off**.
4. On the first-run question, answer **Automatic**. That exercises everything, including the path searches.
   The first 30 s window holds that initial pass, and the report skips it.
5. Use the same routine in both runs:
   - 0:00–3:00: game at 1x, camera over the network, don't touch anything (steady state),
   - 3:00–4:00: open the station window of your busiest station and leave it open,
   - 4:00–5:00: open the line manager and select ~10 lines.
6. Quit to the main menu **without saving**. Load `aat-perftest` again, set **Implementation = Optimized**, give the same
   first-run answer, and repeat step 5.
7. `uv run plans/zhenya_auto_assign_terminals/perf_report.py`

If you restart the game between the runs, copy `stdout.txt` after the first run, because the game rewrites it on start.
Then pass both files: `perf_report.py run1.txt stdout.txt`.

Quick check that the right code ran: `grep AATPERF stdout.txt | grep start` shows `side=gs start mode=…` and
`side=gui start mode=…` for each load, and the two should agree.

## Reading the report

The numbers that matter most:

- **sweep max ms**: the worst simulation hitch the mod causes. The optimized sweep is capped at about 8 ms per tick.
- **sweep ms/s** and **update ms/s**: the mod's average simulation cost.
- **mod GUI ms per frame**: the mod's share of each frame's budget (16.7 ms at 60 fps).
- **stateBytes**: how much the save and every state copy carry.

The two runs should end up with the same terminals. As a spot check, compare a few lines' stops in the line manager
after each run.

## Known behaviour differences in Optimized

These are intended. Anything else that behaves differently is a bug.

- A changed load config on **existing** vehicles is noticed within about 30–45 s (cached cargo). New or removed
  vehicles are noticed at once.
- A pass over all lines can span several ticks, because each tick does at most about 8 ms of work. So a refresh
  spinner or a player edit can take one extra pass to settle.
- Cards and buttons update every 0.25 s instead of every frame.
- The first check after loading (or after switching implementation) re-checks every line once, because the
  signature format changed. Terminals stay the same.
- Two engine paths are typed in the API but unverified in game: partial reads through `state_native` and
  `get_native`. If they fail, the code falls back to the full copy. You'd see `readStateFull` or `stateGetNative`
  not dropping in the report, and then fix #1/#2 isn't really in effect.

## Afterwards

Unlink (`rm` the `square_aat_perftest` symlink in `staging_area`, or `make unlink`) and re-enable the original mod.
Do it from the main menu.

## Results

### Run 1 (2026-10-09, 250 lines, about 1 min measured per mode, routines not matched)

| | Original | Optimized |
|---|---:|---:|
| sweep max ms (worst sim hitch) | 39.7 | 9.8 |
| sweep ms per real second | 27.4 | 13.0 |
| vehicles read per second | 1,697 | 594 |
| mod GUI ms per frame | 0.586 | 0.022 |
| GUI state copies per second | 84 | 3.6 |
| stateBytes | 65,910 | 65,522 |

- The game-bar widget's cost is gone (32.6 → 0.003 ms/s).
- The signature shrink (#2) did nothing on this save: its stations are small, so the tag strings were already short.
- A ~10 ms `readState` spike remains in Optimized, on the station card (likely opening the station window).
- The sweep runs ~1.7×/s across the simulation VMs, not once per 2 s interval. Each VM seems to sweep on its own.
  Neither version fixes this; it's the next candidate.
- Initial pass: Original sent 22 line updates (250 lines assigned), Optimized 24 (253). They should match exactly on the
  same unsaved save. Not verified yet whether the 2 extra are a behaviour difference or timing (retries, builds).
