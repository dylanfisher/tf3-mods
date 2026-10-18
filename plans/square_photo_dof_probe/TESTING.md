# Testing: DoF probe (DEV)

Status: nothing run yet (built 2026-10-14).

Mod: `mods/square_photo_dof_probe/` (DEV, never upload). Shader: copied by hand into the game install (a mod
can't do it). Log lines start with `[SQDOF]`: `make logs-grep PAT='\[SQDOF\]' ARGS='--session last'`.
Don't run Photo Mode at the same time (both switch the environment).

## Setup

1. Quit the game. `sh plans/square_photo_dof_probe/shader_install.sh install` (backs up the base file to
   `.cache/sqdof_backup/`, copies `shader_files/.../misc/ssr_apply.fs` into
   `~/Library/Application Support/Steam/steamapps/common/Transport Fever 3/base/content/rendering/programs/shaders/misc/`,
   deletes the cached `rendering_programs_ssr_apply.prog_*` files in
   `~/Library/Application Support/Steam/userdata/<n>/3493540/local/shader_cache/`). It refuses if the game file
   is not the build 40420 base (game update or another shader mod such as Realistic Environment Pro).
2. `make link` (stages the new mod). Start the game; the first load may say "Initial shader generation".
3. Enable "DEV DoF Probe" in the mod list, load any save on a base climate (Dry, Temperate, Tropical, Subarctic).
4. Graphics settings: note them, then turn **Reflections on** for T1-T4 (T5 turns it off again).

## T1 install marker

- Look at the four screen corners: a small magenta square (6 px) in one corner = the probe shader runs.
- No square: (a) Reflections off -> T5's question; (b) the copy didn't take: `shader_install.sh status`, delete the
  whole `shader_cache` folder (REP's advice), restart; (c) compile failure: `make logs-grep PAT='Invalid parse|Invalid
  link|include file|Shader' ARGS='--session last'` and paste the lines.
- Also report: anything else different in the picture with the mod button at "SQDOF off" (it must look normal).

## T2 channel (debug mode)

- Click the top-bar button "SQDOF off" four times to reach "SQDOF debug" (each click logs `[SQDOF] mode N ...`).
- Expect: left half of the screen a blurred picture (dark red = no mip chain, `maxNumMips < 1`), right half a grey
  depth image (near white, far dark), a green vertical centre line.
- Nothing changes but the log says `mode 4 debug on`: latitude doesn't reach the shader (or is clamped). Then set
  `#define SQDOF_FORCE_MODE 4` in the probe file, `install` again, restart: shows whether the effect itself works.
- **Sun check:** before the first click and in debug mode, compare the sun's position and shadows (screenshot both,
  same time of day, paused). Moved sun = latitude isn't periodic on the CPU side: report it.

## T3 tilt-shift

- Click back round to "SQDOF tilt" (from debug: off, then tilt). Camera on a town from above at ~45 degrees.
- Expect a sharp horizontal band in the middle third, blurred top and bottom. Report: blur strength, halos at
  edges, banding, whether the UI is affected (it shouldn't be: the pass is before the UI).

## T4 depth of field

- "SQDOF dof": aim the screen centre at a nearby vehicle or house with background behind it. Expect it sharp and
  the background (and very near foreground) soft; move the camera so the centre hits something far away: the focus
  follows. "SQDOF dof_shallow": a much thinner sharp zone.
- Report: does focus follow, halos around sharp objects against a blurred background (expected: the blur ignores
  depth edges), flicker while moving, frame time (FPS overlay or feel), what the sky does.

## T5 Reflections off

- Turn Reflections off in the graphics settings (no restart if the game allows). Is the magenta square still
  there? Does "SQDOF dof" still blur (and the debug left half: red = no mip chain without SSR)?
- This decides whether a Photo Mode DoF would need Reflections on.

## End (always)

- Button to "SQDOF off" (or Esc: the pause menu switches back). Quit the game.
- `sh plans/square_photo_dof_probe/shader_install.sh restore` (or Steam > Transport Fever 3 > Properties >
  Installed Files > Verify integrity). `status` must say "base". Put Reflections back as noted.
- Disable the mod in the mod list (from the main menu, never with a save loaded).

Report per test: what you saw (screenshots welcome), plus the `[SQDOF]` lines and any shader log lines.
