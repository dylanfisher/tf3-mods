# Hitch probe: does a game-script pause drop frames?

DEV mod: `mods/square_hitch_probe` ("DEV Hitch Probe", **not for upload**). Question it answers: when a game
script's `update` runs long (Auto Assign Terminals' sweep: 39.7 ms worst tick on 250 lines, PERFTEST.md run 1),
does the rendered frame wait for it (a visible hitch), or does only the simulation fall behind?

## How it works

- A **button in the top-left mod area** ("Hitch: off") cycles the levels `off → gs20 → gs40 → gs100 → gui40`.
  Each load starts at `off`.
- At a `gs` level the game script busy-waits that many ms about every 2 s (every 40 ticks), inside `update`, the same place
  a sweep runs. At `gui40` the GUI's `react.onStep` busy-waits instead: the control, which must show up as a slow
  frame and proves the frame log sees hitches.
- The GUI times every frame (`react.onStep`, Main Thread) with `api.type.Clock` and logs them in chunks of 240.
  Both sides log `GAME_TIME.tickCount`, which is how the report lines a pause up with the frames around it.
  The API docs say it ticks once per frame, but in game it moves by 4 once per simulation step (~200 ms, ~20/s),
  so the matching is only as fine as one step plus a frame window. Each Clock only counts from its own creation, so it can't be compared
  across Lua states. That's why the tick is used.
- Lines: `[HITCH] ...` in `<userdata>/crash_dump/stdout.txt`. Format in `hitch_report.py`'s docstring.

## Running it (Run A, about 6 minutes)

1. From the main menu: `make link`. Load a **copy** of a big save (the level is stored in the game-script state)
   with "DEV Hitch Probe" enabled. Other mods can stay on, but turn off Auto Assign Terminals (and its fork and
   the perf test) so their sweeps don't add pauses of their own.
2. Game at 1x. For **each level**, at least 60 s each (time it; the report flags shorter ones): click the button until it shows the level, then pan and zoom
   the camera over a busy area the whole minute. Note for each level whether you can *feel* a hitch.
   Order: `off`, `gs20`, `gs40`, `gs100`, `gui40`.
3. Quit to the main menu (no need to save), then: `uv run plans/hitch_probe/hitch_report.py`.

## Reading the report

One row per level: fps, median/p99/max frame time, slow frames per minute, and **hit**, meaning pauses followed
(within ~6 frames before to 40 frames after the first frame showing the pause's simulation step) by a frame
slower than median + half the pause. Levels shorter than 45 s are flagged "(too short)".

- `gui40` should hit nearly every pause. If it doesn't, the frame log is broken: stop and fix that first.
- `off` gets the same test at every 40th tick (`ctl40`): the false-alarm rate.
- **`gs40` hits like `gui40`:** the renderer waits for the game script. A 40 ms sweep is a 40 ms frame hitch, and
  the fork's 8 ms budget matters for smoothness.
- **`gs40` hits like `off`:** only the simulation stalls; the camera stays smooth. The sweep fix then matters for
  vehicle motion at most, and the GUI fixes (the gist) were what players felt.
- `gs100` shows what a much bigger network's sweep would do.
- A "more than one game-script pause per period" note means `update` ran in parallel Lua states. That's worth
  knowing for AAT's ~1.7 sweeps/s too.

## Afterwards

Disable the probe in the mod list, or `make unlink`, from the main menu (never while a save is loaded).

## Run B (only if gs40 hits)

Add the same frame logger to `mods/square_aat_perftest` and redo PERFTEST.md's routine, to count slow frames near
real sweeps for Original vs Optimized.
