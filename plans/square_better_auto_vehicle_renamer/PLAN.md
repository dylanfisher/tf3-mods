Status: revision 1, not released. Planned 2026-10-19, phase 0 partly done 2026-10-20, phase 1 (core modules,
settings, translations, tests) done 2026-10-20, phases 2 (game script) and 3 (welcome window) built 2026-10-20, three options (per line counting, old-vehicle
mark, train length) and the fleet register console command added 2026-10-20 ("Options" below), sweep strategy
reworked for a lower steady-state cost 2026-10-20 ("Sweep strategy (2026-10-20)"; the old cycle in `HISTORY.md`);
first in-game runs 2026-10-20 (sessions `2026-10-20_0539_sqot-sqfn` and the 07:53Z one, `TESTING.md`), then the
rename lease and the pass log lines ("Rename lease (2026-10-20)"); after the 08:12Z run (a 483-name re-render) the
sticky lease and the run lines (`pass` / `rerender` progress and done, same section), passed in game in the 19:28Z
run (`HISTORY.md`); after it, one init line per load (a wall clock tells a late Lua state from a reload), the run
fields kept at load, the lease dropped only at a new load ("One init per load", same section); the rest of the first run is `TESTING.md`. Name "Better Auto Vehicle Renamer", modId
`square_better_auto_vehicle_renamer` (log tag `[SQFN]`, kept from the working name "Fleet Numbers").

# Better Auto Vehicle Renamer: automatic vehicle names

Gives every vehicle a permanent fleet number and its model name, like a real operator's fleet register:
`Sternwheeler S-0012`, `Citaro B-0412`, `Class 101 L-0045`. Line namers name lines; nothing on mod.io does this
well (survey 2026-10-19: Auto Vehicle Renamer is a hard-coded `<line> 00`, German only, 37 % rating; Line Classes &
Fleet renames vehicles as a side feature; Gameburrow's Destination Displays writes destinations into names).

## Decisions (user interview 2026-10-19)

| Question | Answer |
|---|---|
| Home | standalone mod (works next to any line namer, LMP included) |
| Default name | fleet number, model, purchase year: `B-0205 \| Daimler Deck Seat Car (1934)` (user 2026-10-20; was model + number) |
| Counting | one counter per transport type, a letter each (table below) |
| Sold vehicles | the number is retired, never reused (numbers only go up) |
| Replace Vehicles | same number, new model name (`Old Bus B-0412` becomes `New Bus B-0412`) |
| Model on a consist | the first powered part (loco / power car), else the first part |
| Hand-typed names | detected and left alone |
| Existing vehicles | a first-load dialog (Smart Lanes welcome pattern) asks whether to number them all, oldest first |
| UI | mod settings only for v1; the welcome window is the only window |
| Destination Displays active | detect it, log it, say so in the welcome window and rename nothing |
| Helicopters | own letter H (2026-10-20) |
| Freight trains | no own letter: all trains are L (2026-10-20) |
| Numbering the fleet later | a mod setting "Number existing vehicles on next load" (2026-10-20) |
| Restore original names | not now (2026-10-20); `orig` is still recorded so it can come later |
| Mod name | Better Auto Vehicle Renamer (2026-10-20) |
| More options (2026-10-20) | Counting "Per line" (`Bus 12 #03`, gaps close), a mark on vehicles past their lifespan, the train length; all Off (user 2026-10-20, after briefly trying Wagons as the default), the default name stays `B-0205 \| Daimler Deck Seat Car (1934)` ("Options" below) |
| Fleet register | a console command printing every fleet number (`[SQFN] REG`), like Organic Towns' `who()` (2026-10-20) |

## Types and letters

| Type | How it's told apart | Letter |
|---|---|---|
| Bus | carrier ROAD, carries passengers | B |
| Truck | carrier ROAD, no passenger capacity | T |
| Tram | carrier TRAM | R |
| Train | carrier RAIL | L |
| Ship | carrier WATER | S |
| Aircraft | carrier AIR, not a helicopter | A |
| Helicopter | carrier AIR, model `metadata.airVehicle.isHelicopter` (fallback: `vehicle/helicopter/` in the model path) | H |

Carrier enum values (console 2026-10-20): ROAD 0, RAIL 1, TRAM 2, AIR 3, WATER 4.

## How it works

**Where it runs.** The game script's `update` (the auto_line_namer / Destination Displays pattern; research
2026-10-19). There is no vehicle-bought / sold / line-changed event (none in tealdefs, base code or mods), so:
- a cycle is due when its interval has passed in game time (2 s windows, `math.floor(t / 2000)`, stretched up to
  10 s while nothing changes). `update` runs in about 11 Lua states ("Sim Pool 1-11"; docs/findings/game-scripts.md),
  so each keeps its own timer, id set and caches; the state is the shared store, and one Lua state at a time sends
  renames (the rename lease).
- each cycle lists `getEntitiesWithComponent(TRANSPORT_VEHICLE, { requireOwnedByPlayer })` and diffs it with that
  Lua state's previous list; only new ids, vehicles not settled yet, expiries due and a small backstop slice get a
  `getComponent`, inside `pcall` ("Sweep strategy (2026-10-20)").
- renames per sweep are capped (start at 10, which stays below anything seen working; towns did ~2 per tick, 30/30
  ok), so a 2000-vehicle first pass spreads over a few minutes. It's logged with progress.
- each vehicle is re-checked with `entityExists` right before its command. Vehicles in `GOING_TO_DEPOT` are skipped
  (the sell-on-arrival crash class: `docs/findings/lines-vehicles.md`).
- the sweep keeps a local used-names table, because the commands take effect later.

**Performance (user 2026-10-20: "always implementing with performance in mind, staying off main thread").**
- All work runs in the game script's `update` (sim threads, off the main / render thread). The GUI script runs only
  the welcome window: a 1 s `react.onStepTimer` joins a tick onto the main thread that reads a few state fields
  (`state_native:find`) a few seconds after load, then never again in that load (the timer cannot be removed; once
  decided it only returns). No `onStep`, no `guiUpdate`, no per-frame work (phase 3).
- A settled fleet costs one id list and a set diff per cycle (every 10 s game time when idle) plus the backstop
  slice (25 vehicle reads per game second), not one read per vehicle per cycle ("Sweep strategy (2026-10-20)"). At
  most 200 vehicles are read per `update`, plus the rename budget. Hard caps on every loop (CLAUDE.md), with a log
  reason when hit.
- A vehicle that is read costs one `getComponent(TRANSPORT_VEHICLE)` plus one string compare. The name is
  rendered only when an input changed: a per-vehicle input key (line id + line name + lead model id + settings
  hash + the "old" flag + the train count, and in the register check the number shown), compared before any string
  building. Model names are cached per model id; line names per line, refreshed by the line watch (only with a
  setting that shows the line).
- `state:set()` only when something changed (renamed, new or pruned records), never once per tick. The record
  stays small (numbers and short strings). `state:get()` only when a slice needs the register (phase 2: "The lazy
  register read").
- SQPERF timing on the sweep (`[SQFN]` / SQPERF lines) with the shared debug setting; target under 0.5 ms per
  `update` on a 2000-vehicle save.
- No pass work while the game is paused (`GAME_SPEED.speedup` 0: lines-vehicles finding).

**Per-save state** (`state:get()` / `state:set()`, never `get_native`; versioned; full layout in
`bavr_register.lua`'s header):
- `nt[letter]` / `na` / `nm[model key]`: the next fleet number per type, for "One for all" and per model; `nj` the
  next line-join sequence number ("Options": per line).
- `v["<id>"] = { k, t, a, m, mk, pt, li, lj, lp, last, orig, user, ts, rc }` (ids as string keys): letter, the three
  numbers, the per-model number's model, purchase time of part 1 (catches a reused id after a sale), line, its join
  sequence number and position on that line (per line counting), the name we last set, the name before we touched
  it, the player-named flag, and the pending-send time and count.
- `welcome`: the first-load answer (`apply` / `later`), `cutoff` (Not now), `pass` (Apply due), `count` (for the
  window); `standDown`: the reason when a conflicting mod is active; `win` / `used`: the shared rename budget;
  `lo` / `le` / `lq`: the rename lease (the one Lua state that sends renames, until game ms `le`, epoch `lq`;
  "Rename lease"); `ptotal` / `pdone`: the Apply pass's vehicle count and renames sent while its renames run, `rh`
  (the settings hash the names were rendered with), `rb` / `rr` (a re-render's names and renames sent), `plog` (the
  last progress line): the run lines ("Rename lease", run lines);
  `gone`: just-pruned records for Replace matching; `words` (the GUI's translated type words), `sdSeen` (the
  stand-down notice was shown), `boot` / `bootT` (game ms and wall-clock seconds of a load's first init: one init
  log line per load) since phase 2.
- pruned once per cycle: an id that's gone is dropped (a changed purchase time on another line drops it too). Its
  numbers stay retired because the counters only grow.

**Naming one vehicle.**
1. Classify it into a letter. A type switched off in the settings is skipped.
2. Find its record. If there is none, it's a new vehicle (or an existing one after Apply): take `next[letter]`.
3. Model name: the first part with power, else part 1, `modelRep.get(id).metadata.description.name` (as LMP's
   vehicle_hover does).
4. Render `{model} {letter}-{number:04}` per the format setting, cut to 50 UTF-8 characters by shortening the
   model, never the number (the base text field's cap; Destination Displays' `utf8Prefix`).
5. Send only if the current name differs and we may touch it (below).

**Hand-typed names.** We may rename a vehicle while its current name is the game default (`^%D.-%s%d+$`:
`Road Vehicle 263`, `Train 13`, `Ship 76`, `Aircraft 2` in an English game, console 2026-10-20; a default name has a
NAME component too, so only the text tells it apart; recorded as `orig`) or exactly what we last set (`last`). Any other name means the player
typed it: set `user = true` and never touch it again. The vehicle keeps its number in the register, so the
counter doesn't shift. If the player clears the name back to empty or default, we take it over again.

**Replace.** If replacing keeps the entity id (to probe), the record stays and step 3 picks up the new model on
the next sweep. If it creates a new id, we match the gone vehicle to the new one by line plus position in the same
sweep. Failing that, it gets a new number, which is logged.

**First load of a save** (welcome window, a copy of `sl_bg.script.lua`'s: GUI script, base widgets, inline style,
no stylesheet rules). Shown once per save when `welcome` is unset and the save already has vehicles (a new game with
none just records `apply` silently). It reads: what the mod does, "Number your 312 existing vehicles, oldest first"
(a checkbox, ticked), "Save your game first, so you can go back if you change your mind", and the buttons [Apply]
[Not now]. The GUI sends the answer to the game script as an event.
- Apply: every existing vehicle with a default name, sorted by purchase time, gets numbers in order; hand-named
  vehicles get a number in the register but keep their name.
- Not now: existing vehicles are left as they are (no record; `cutoff` = the answer's game time marks them, phase 1)
  and only vehicles bought from now on get numbers. Closing the window counts as Not now.
- Later: the mod setting "Number existing vehicles on next load" (No / Yes) runs the Apply pass on the next load of
  any save that answered Not now (the welcome window shows again, with the box ticked). The setting stays as set,
  so a save numbered once is not numbered again (the pass only touches untouched default names).
- Until the answer arrives, the sweep renames nothing (no change to a save without consent).

**Conflicts.** Destination Displays (`gameburrow_destinationdisplays`) is active means stand down entirely: one
`[SQFN]` log line and one line in the welcome window. Detected by its key in `api.engine.config.getModParams()`
(every active mod has an entry: docs/findings/scripting.md; its real modId checked in `.cache/subscribed/`), read once
per Lua state per load (phase 2). `ug_require` of one of its modules was rejected: they are Teal modules with code at
load. Our own mods don't rename vehicles.

**Save safety.** `severityAdd` / `severityRemove`: None. Names are ordinary NAME data the game keeps without the
mod. Removing the mod leaves the names; the state is ignored. Nothing changes before the welcome answer.

**Settings (mod.json, 13 languages; user 2026-10-20: "plenty of naming options, like auto line namer").**
Values are 1-based option indices (CLAUDE.md); defaults in bold. Every value's label shows an example.

| Key (`bavr.*`) | Setting | Values |
|---|---|---|
| `format` | Name format | Model + number (`Citaro B-0412`) / **Number + model** (`B-0412 Citaro`) / Number only (`B-0412`) / Model (number) (`Citaro (B-0412)`) / Line + number (`Bus 12 · B-0412`) / Number + line (`B-0412 · Bus 12`) / Model + line + number (`Citaro · Bus 12 · B-0412`) |
| `model` | Model name | **Full** (`Mercedes-Benz Citaro`) / Short: drop the first word when there are 2+ (`Citaro`) / First word (`Mercedes-Benz`) / Up to 12 characters |
| `prefix` | Type prefix | **Letter** (`B`) / Short word (`Bus`, `Trk`, `Trm`, `Trn`, `Shp`, `Air`, `Hel`) / Full word (`Bus`, `Truck`, `Tram`, `Train`, `Ship`, `Aircraft`, `Helicopter`; translated) / None (`0412`) |
| `numSep` | Between prefix and number | **Dash** (`B-0412`) / None (`B0412`) / Space (`B 0412`) / Dot (`B.0412`) / Slash (`B/0412`) |
| `partSep` | Between name parts | Automatic (a space after the model, ` · ` around a line name) / ` · ` / ` - ` / **` \| `** (default since 2026-10-20) / `, ` |
| `digits` | Number digits | 1 (`412`) / 2 / 3 / **4** (`0412`) / 5 (`00412`) |
| `start` | First number | **1** / 100 / 1000 |
| `counter` | Counting | **Per type** (B-0001, T-0001 …) / One for all (B-0001, T-0002 …) / Per model (Citaro 01, Citaro 02 …; the number restarts per model) / Per line (`Bus 12 #03`; "Options") |
| `year` | Purchase year | Off / **After the name** (`B-0412 \| Citaro (1925)`) / Before the number (`Citaro 1925-0412`) |
| `old` | Mark vehicles past their lifespan | **Off** / Hourglass (`B-0412 \| Citaro ⌛`) / Star (`… *`) / Word (`… (old)`, translated) |
| `trainLen` | Train length | **Off** / Wagons (`L-0045 \| Class 101 +8`) / All units (`… Class 101 ×9`) |
| `lineName` | Line name in names | **Full** / Up to 12 characters / Line number only (the first number in the line name, else the full name) |
| `takeOver` | Hand-typed names | **Keep them** / Rename them too |
| `renumberNext` | Number existing vehicles on next load | **No** / Yes |
| `speed` | Renaming speed | Slow (5 per check) / **Normal** (10) / Fast (25) |
| `type.bus` … `type.heli` | 7 Off / On buttons: Buses, Trucks, Trams, Trains, Ships, Airplanes, Helicopters | **On** |
| `sqperf_log` (no `bavr.` prefix) | Debug: performance log | **Off** / On (shared SQPERF wording and key) |

Rules for the settings: the name updates when an input changes (line renamed or changed, model replaced, a setting
changed at load). The fleet number never changes, except with `counter` = per model, where a replaced model takes the
next number of the new model (logged), and per line, where the position closes up when a vehicle ahead leaves the
line ("Options"). With a line format, a vehicle with no line uses the model instead (`Citaro
B-0412`). Every rendered name is cut to 50 UTF-8 characters by shortening the model, then the line, never the
number, the year, the old-vehicle mark or the train length. A setting changed between loads re-renders our names on the next sweeps (budgeted), never hand-typed ones.

**Log.** `[SQFN]` lines: `welcome op=show|answer`, `sweep n= renamed= skipped= old= lineMoved= lineWait= budget=`,
`pass progress a/b` and `pass done n=`, `rerender progress a/b` and `rerender done n=`, `replace matched|new`, `standDown reason=`; the console's `REG` lines
("Options").

## Phases

0. **Console probes** (cheapest first; record the results in `docs/findings/lines-vehicles.md`):
   read a vehicle's name and NAME component (is it nil for a default name?); rename one, read it back and reload the
   save; `transportVehicleSystem.getVehicleNames(carrier)` for each carrier's default word; does Replace keep the id
   and name; does the base vehicle list sort `B-0412` / `B-1000` sensibly; a 40-vehicle rename burst (rate,
   failures). Snippets: below.
1. **Core** (done 2026-10-20; "Phase 1" below): five pure modules in `content/better_auto_vehicle_renamer/`,
   tests in `tests/square_better_auto_vehicle_renamer/`.
2. **Game script** (built 2026-10-20; "Phase 2" below): sweep, state, events, stand-down, SQPERF, the logs. The
   game run (buy, sell, rename by hand, replace, 200+ vehicles) is `TESTING.md`.
3. **Welcome window** (built 2026-10-20; "Phase 3" below), GUI script and the answer event; `make css-rules` 0.
3b. **Options** (built 2026-10-20; "Options" below): per line counting, old-vehicle mark, train length, the fleet
   register console command.
4. **Release**: 13 languages, tooltips, cover and slides, description with Changelog, presence marker, `make
   gate-full`.

## Phase 1 (2026-10-20): core modules

Pure Lua (pre-5.3, no `api.*` at load or anywhere: game reads come in through a `reader` table), in
`mods/square_better_auto_vehicle_renamer/content/better_auto_vehicle_renamer/`; each file's header documents its API.

| Module | Entry points |
|---|---|
| `bavr_settings.lua` | `Settings.parse(getModParams()[MOD_ID] [, words])` -> `cfg` (indices -> values, `enabled[letter]`, `budget`, `hash` of the render settings + full words) |
| `bavr_classify.lua` | `Classify.letter(carrier, hasPassengers, isHeli)`, `isHeliModel(metadata, path)`, `lead(n, isPowered)`, `hasPassengers(metadata)` |
| `bavr_text.lua` | `Text.render(cfg, model, line, letter, number, year)`, `modelName(cfg, full)`, `lineName(cfg, full)`, `isDefault(name [, words])`, `ulen`, `uprefix`, `fleetId` |
| `bavr_register.lua` | `Reg.new / validate(state:get())`, `create`, `shown`, `setModel`, `prune`, `takeGone`, `answer(st, "apply"\|"later", now)`, `welcomeDue(st, cfg, count)`, `assignPass`, `key` |
| `bavr_sweep.lua` | `Sweep.newRuntime()` (one per Lua state), `Sweep.step(st, rt, cfg, reader, nowMs)` -> phase; renames in `rt.ops` / `rt.nops`; `rt.dirty` -> `state:set`; `rt.stats` for the log |

Phase 2 wires `update`: `st = Reg.validate(state:get())`, `Sweep.step`, send `rt.ops` without a callback, `state:set(st)`
only when `rt.dirty`; not called while paused. The `reader` contract (list / read into a reused buffer / modelInfo /
lineName / exists) is in `bavr_sweep.lua`'s header. Phase 3 calls `Reg.welcomeDue` and sends the answer as an event
the game script applies with `Reg.answer`.

Choices made where the plan was open or silent:
- **Three numbers per record** (per type `t`, global `a`, per model `m` + model key `mk`), all taken when a vehicle is
  first numbered, so switching "Counting" never renumbers and switching back restores the old numbers.
- **Not now keeps no records**: `st.cutoff` (game ms) marks the answer; a vehicle without a record bought before it is
  untouched. The state holds records only for numbered vehicles. Apply sets `st.pass`: one full cycle collects the
  unnumbered vehicles (per Lua state, in `rt`), then numbers them oldest first (purchase time, then id); new vehicles
  wait until then, so the order holds.
- **Per Lua state**: the vehicle list, the cursor and all caches (model info, line names per cycle, the fast-path
  inputs) live in `rt`; numbers, records, the welcome answer, the 2 s rename budget (`win` / `used`) and the rename
  lease (`lo` / `le`, "Rename lease (2026-10-20)") live in the state. Each Lua state cycles on its own; a record of a
  vehicle bought after a state's list is never pruned by it.
- **Cycle**: `list` -> `prune` -> `scan` -> `end` (the pass); since 2026-10-20 with the list diff, the backstop, the
  line watch and the back-off ("Sweep strategy (2026-10-20)"; the phase 1 cycle is in `HISTORY.md`). The fast path is
  one `reader.read` and five equality checks; a name is rendered only on a changed input or a name that is not ours.
- **Replace keeping the id** (the base code keeps the entity: `makeVehicleReplaceCmd(entity, config)`,
  `vehicle_react_util.tl:405-408`, `docs/findings/gui.md`; not yet confirmed in game, `TESTING.md` D): a changed purchase time on the same line and type keeps the numbers; on
  another line it is a reused id (new number). A **new id** on the same line and type within 10 s (`GONE_MS`) of a
  pruned record inherits its numbers (`rt.matchGone = false` turns this off if Replace keeps ids).
- **Pending sends**: a sent name is not re-sent for 10 s (`PENDING_MS`), at most 3 times (`RETRY_MAX`); seeing the
  name arrive clears it. Two vehicles that would get the same name in one cycle: the second waits for the next cycle.
  With "Per model" counting and a format without the model, names can repeat across models (allowed for now).
- **Cap at 50 characters**: the model is cut to 12 characters, then the line to 12, then the model, then the line,
  never the number or year (cutting the model to nothing first lost it next to a long line name).
- **Year "Before the number"** replaces the type prefix (`Citaro 1925-0412`).
- `orig` is recorded at the first rename but is not a may-touch rule (a hand name kept with "Rename them too" would
  otherwise be taken over again later).

Corrections to this plan (fixed above): the module was planned as one `fn_core.lua` with tests in
`tests/square_fleet_numbers/`; the debug param is the shared `sqperf_log` key (SQPERF's gate reads that key), not
`debugPerf`; the type switches are Off / On Button params like every other square mod (no mod.json `CheckBox` is in
use anywhere), and the aircraft switch is named "Airplanes" (the full prefix word "Aircraft" is its own translation
key); the default part separator was "Automatic" at first (the settings examples `Bus 12 · B-0412` assumed it); since 2026-10-20 it is Bar (` | `), see the settings table.
The default-name pattern is matched with ASCII white space instead of `%s`: under the test Lua, `%s` matched byte
0xA0, the second byte of "Š", and split a UTF-8 character (the game's C locale may differ; ASCII is safe either way).

Gate 2026-10-20: `make gate`: tl_check 6 files 0 errors, validate warn only (`0.png` missing, phase 4), 41 tests
pass (full mode 3.7 s). `make i18n --check --lint-modinfo` OK (93 keys), `make tooltips` 0 long lines. A settled
2000-vehicle fleet costs 0.09 ms per 200-vehicle slice in `Sweep.step` with a fake reader (`test_sweep.lua` "cost").
SQPERF is not in yet (phase 2, with the game script). "More from square" is written into `description.html`; the mod
still needs a group in `branding/more_from.json` when it is published.

Open for phase 2 (from phase 1), answered in "Phase 2" below: the `state:get()` cost (designed around; measured in
the first game run, `TESTING.md` first item), full type words (sent by the GUI), the purchase year
(`getCalendarDate`), bus vs truck (the reader converts the metadata to plain tables), the "Not now" wording
(matches). Still open: `cosmetic` is false for now (it renames entities): decide with the achievements question in
phase 4.

## Phase 2 (2026-10-20): game script

Files in `content/better_auto_vehicle_renamer/`: `bavr.gs.lua` (registration, found by extension like Smart Lanes'
`sl_lanes.gs.lua`: `updateScript` / `handleEventScript`), `bavr.script.lua` (thin glue: builds the env on the real
API, pcall around everything, exports via `data()`), `bavr_game.lua` (the logic per Lua state, env-injected, tested),
`bavr_reader.lua` (the sweep's reader on the API), plus `content/sqperf/` (`make sqperf-sync`).

- **Update, per Lua state**: subscribe to the GUI event once per load (`subscribeToNoEvents` + `subscribeToEvent`;
  subscriptions are saved with the game: docs/findings/scripting.md), init once (settings, stand-down, the init log
  line), then while the game runs one `Sweep.stepLazy` slice; renames are sent without a callback
  (`makeEntitySetNameCmd`, `entityExists` checked again right before the command); `state:set` only when
  `rt.dirty`. Paused (`GAME_SPEED.speedup` 0) or `dt <= 0`: returns at once (no list, no read). Cadence: "Sweep
  strategy (2026-10-20)" (the phase 2 cadence is in `HISTORY.md`); the rename budget per 2 s window shared in the
  state, spent by the one Lua state holding the rename lease ("Rename lease (2026-10-20)").
- **The lazy register read** (the phase 1 risk: `state:get()` may copy the whole register per call; 2000 records
  copied per update were ~4 ms in the fake). `Sweep.stepLazy(rt, cfg, reader, now, fetch)` reads the state (fetch =
  `state:get()` + validate) at most once per update, and only when the slice needs it: each vehicle first meets a
  per-Lua-state check that needs no register (the inputs this state last confirmed for a name of ours: name,
  purchase time, line, line name, lead model, settings hash; or a hand-typed name / an untouched "Not now" vehicle it
  saw, with the same purchase time and line). Only a vehicle failing it reads the register (once for the slice).
  "prune" reads it when a vehicle of this state's previous list is gone, while the answer or a pass can still change
  (unanswered; "Not now" with "Number existing vehicles on next load" Yes; a pass due), and every 30 s game time
  (`PRUNE_MS`; was every 15 cycles, `PRUNE_EVERY`, until the idle back-off made cycles longer) as a backstop. A settled
  fleet: about one read per 30 s per Lua state, no writes (`test_game.lua` "state reads"; `test_sweep.lua` "cost"). The
  first read of each Lua state runs the full `Reg.validate` (it walks every record); later reads `Reg.validateLight`
  (top level only: only this code writes the state).
- **Numbers from a fresh state**: a number is only taken in an update that read the state in that same update, and
  that update writes it at its end (never from a cached copy). Two Lua states racing could still lose a write (a get /
  set pair is not atomic), so each Lua state remembers the highest number of each counter it has written
  (`rt.hiT` / `hiA` / `hiM`); a later read whose counter is not above it moves the counter past it (`stats.race`, in
  the sweep line): a number is never handed out twice even then. First game runs: `race=0` throughout
  (`2026-10-20_0539_sqot-sqfn`).
- **Stand-down**: the key `gameburrow_destinationdisplays` in `getModParams()` (read once per Lua state per load) ->
  `standDown = "destination_displays"` in the state (for the welcome), `[SQFN] standDown reason=destination_displays
  renamed=none` with the init line, no sweep in that load. Without the mod the next load clears it.
- **Full type words**: `_()` in a game-script state is unverified, so the GUI script (which translates) sends the 7
  words once per load when the state holds other ones (event op=words, stored as `st.words`; every Lua state picks
  them up at its next read). With the "Full word" prefix the sweep waits up to 30 s game time for them
  (`WORDS_WAIT_MS`), then uses English (`words src=english reason=timeout`). The init line logs `gsTr=`, the game
  script's own `_("Truck")`: one German load answers the open question.
- **Purchase year**: `api.engine.util.getCalendarDate(purchaseTime).year`, the base game's own conversion of a past
  game time to a date (`notification_log.tl:151`, `finances_charts.tl:280`, and in a game script
  `deliver_workers.script.tl:78`). It follows the calendar speed the game ran at (`GAME_TIME.dates` anchors), unlike
  dividing by `getDefaultYearDuration` (docs/findings/gui.md "Vehicle age units"). Read only with the year setting on,
  once per purchase time (cached). Offline only the wiring is tested (a fake `getCalendarDate`); the game run checks
  the years.
- **Reader**: `getEntitiesWithComponent(TRANSPORT_VEHICLE, { requireOwnedByPlayer = getPlayer() })` (Destination
  Displays' call); per vehicle `entityExists` (the tealdef: `getComponent` needs an existing entity, and a listed id
  can be sold since) + `getComponent` + `getEntityName`; the line guarded `type == "number" and > 0 and
  entityExists` (once per line per list); lead part = the first part whose model has power (land engines' power, a
  ship's `availPower`, an aircraft's `maxThrust`), cached per model; model metadata converted to plain tables, pcall
  per field (userdata raise on unknown fields), for `Classify.hasPassengers` / `isHeliModel`.
- **Log** (`[SQFN]`, never per vehicle): `init welcome= records= count= pass= standDown= format= prefix= counter=
  year= old= trainLen= speed= words= hash= rh= run= gsTr=` once per load (`hash` the settings hash, `rh` the one
  the save's names were rendered with: they differ when a load re-renders; `run=pass:a/b | rerender:a/b | none`, the
  run the load continues; "Rename lease (2026-10-20)", "One init per load"); `sweep n= cycles=
  inspected= fast= renamed= new= deferred= user= untouched= skipped= depot= pruned= matched= replaced= reused=
  modelChanged= failed= dup= gone= gets= race= budget= capped=` (plus the sweep strategy's fields, "Sweep strategy
  (2026-10-20)", and `follow= claims=`: "Rename lease") for cycles with work, at most one per 10 s game time per Lua
  state; `pass created= collected=`; `pass progress a/b` / `rerender progress a/b` and one `pass done n=` /
  `rerender done n=` ("Rename lease (2026-10-20)", run lines; before, every Lua state logged progress, and `N/N` again
  at every load: the 07:53Z session logged 14 `pass progress 410/410` lines at load); `welcome op=answer answer=
  kind= count= button=`;
  `words src=gui|english`; `standDown reason=`; `error where= err=` (5 per Lua state).
- **SQPERF** (`ctx=gs`, setting `sqperf_log`): sections `update`, `get` (state:get + validate), `step`, `set`,
  `event` (and inside `step` since 2026-10-20: `list`, `lines`, `scan`); counter `renamed` (and `insNew`, `insBack`,
  `insQueue`, `insFull`, `carried`); `phase=first` = the first `get` and `step` of each Lua state.

## Phase 3 (2026-10-20): welcome window

Files: `bavr_welcome.res.lua` (a `::ModEntryPointExtension` plugin, like Smart Lanes' `sl_bg.res.lua`),
`bavr_welcome.script.lua` (the window), `bavr_welcome.lua` (pure: decision, example, payloads, and `wrapLine` copied
from Smart Lanes' `sl_allmode.lua`).

- **No per-frame work**: `react.onStepTimer(fn, 1.0)` (a worker thread) joins one tick onto the main thread with
  `react.enqueueJoin` while undecided (Supply Gaps' pattern: the window and the state read are main-thread work).
  The state is read at tick 3, then every 2 ticks, at most 300 times (a paused game counts its vehicles only once it
  runs): `getEntityForGameScript(GS_NAME)` + `GAME_SCRIPT.state_native:find(key)` for a few keys (`ver welcome count
  pass standDown sdSeen words`), never a full copy. Then never again in that load (the timer stays, returning at once).
- **Decision** (`Welcome.decide`): nothing until the game script wrote its state (`ver`) and counted; the stand-down
  notice once per save (`sdSeen`); otherwise `Reg.welcomeDue` ("first" with vehicles; "renumber" after Not now with
  the setting Yes, once the untouched vehicles are counted, which the game script writes to `count` at a cycle end;
  nothing when 0). Never in the map editor.
- **Window**: base widgets, base classes `popover, dialog` (centered), inline padding and spacers only, no stylesheet
  rule (`make css-rules` 0). Lines: (renumber: "You asked to number the existing vehicles on this load."), "Every
  vehicle gets a fleet number and its model name, like %s." (an example under the current settings, `Mercedes-Benz
  Citaro B-0412` by default), "New vehicles get their number when you buy them.", "Names you typed yourself are
  kept." (only with Keep them), the ticked CheckBox "Number your %d existing vehicles, oldest first", the base info
  hint "Save your game first, so you can go back if you change your mind." (Smart Lanes' wording), [Apply] [Not now]
  (Not now's tooltip names the setting "Number existing vehicles on next load", whose own tooltip says "Not now").
  Apply with the box unticked = Not now; closing (X, gamepad back) = Not now. Stand-down: one line and [OK]. Text is
  wrapped in code at 50 columns (CJK double), the CheckBox label too. Gamepad focus, the per-platform Window field
  check and the PS5 info-hint fallback are Smart Lanes' code.
- **Events** (`api.cmd.makeScriptingSendEventCmd("", MOD_ID, "BAVR.gui", param)`): `{ op = "welcome", answer =
  "apply" | "later", number }`, `{ op = "words", words }`, `{ op = "sdseen" }`; the game script applies the answer
  with `Reg.answer` (a second answer after Apply is ignored and logged). Log: `welcome op=show kind= count= tries=`,
  `welcome op=done|skip reason=` (GUI), `welcome op=answer` (game script).
- 14 new strings in all 13 languages (`Apply`, `Not now` and the save hint reuse Smart Lanes' translations; the
  setting name inside Not now's tooltip is the setting's own translation; the window title is the localized mod name).

Fixes and corrections in phases 2 and 3: `Reg.prune` appended `st.gone` in `pairs()` order, so "oldest first" Replace
matching (and `test_register.lua` "prune") depended on the hash order and failed about one run in two; pruned records
are now sorted by purchase time, then id. The fake game's updates use `Sweep.stepLazy`, so every phase 1 sweep test
also runs the lazy read; the stand-down test sets `rt.standDown` (the game script's detection) instead of a state read
per update. "Performance" said the GUI unsubscribes once answered; a react timer can't be removed, so it returns at
once instead (fixed above).

Gate 2026-10-20: `make gate`: tl_check 14 files 0 errors, validate warn only (`0.png` missing, phase 4), 71 tests
pass (full mode too); `make i18n --check --lint-modinfo` OK (107 keys); `make tooltips` 0 long lines; `make css-rules` 0.

## Options (2026-10-20): per line, old-vehicle mark, train length, fleet register

User decisions 2026-10-20: the default name stays `B-0205 | Daimler Deck Seat Car (1934)` (`test_text.lua` "render:
the default name is number | model (year)"), so every option is Off / unchanged by default. All per-vehicle work stays
in the game script's sliced sweep; each option is one more input of the per-vehicle fast path, never a per-sweep
string build. 11 new strings in 13 languages (the Counting tooltip re-keyed); `make i18n` 118 keys.

**Per line counting** (`counter` = "Per line", `Settings` opts `line`):
- What shows: the line name takes the type prefix's place and the number is the vehicle's position on its line, `#`
  and at most 2 digits (`Text.LINE_DIGITS`; "Number digits" 1 gives `#3`, more than 99 shows all digits). With the
  defaults: `Bus 12 #03 | Citaro (1925)`. Per format: Model + number `Citaro | Bus 12 #03`, Number + model `Bus 12
  #03 | Citaro`, Number only `Bus 12 #03`, Model (number) `Citaro (Bus 12 #03)`; the line formats (Line + number,
  Number + line, Model + line + number) show the line once, inside the id (`Bus 12 #03`, `Citaro | Bus 12 #03`).
  "Line name in names" shortens the line there too (`12 #03` with Line number only). Year "Before the number" has
  no prefix to replace, so the year goes after the name. The number separator and the type prefix don't apply.
- A vehicle without a line (or on a line without a name) shows its per-type number with its prefix (`B-0205 |
  Citaro`). Positions start at 1 whatever "First number" says.
- Kept beside the permanent numbers: each record keeps `t` / `a` / `m` and adds `lj` (join sequence number, `st.nj`,
  unique: no two vehicles tie) and `lp` (position). Switching Counting between loads never loses a fleet number; the
  first "prune" of each Lua state in this mode renumbers every line once (positions may be stale from a load with
  another counting).
- Order and gaps (`Reg.linePositions`): by `lj`, then purchase time, then id (stable; the same in every Lua state).
  A new vehicle, or one moved to another line, gets the next `lj`, so it comes last and moves nobody; a vehicle that
  is sold or leaves the line closes the gap: only the ones behind it on that line move up by one. Hand-typed
  vehicles keep their place and their name (so typing a name moves nobody). Replace with a new id (`matched`)
  inherits the gone vehicle's `lj`, so its place: no shift and back. Vehicles with no record (untouched, a type
  switched off) don't count. Not per type letter: a line counts all its vehicles.
- When: the sweep marks a line "touched" when its membership changes (new / matched / reused / moved record, a
  pruned record, a vehicle with no position yet) and renumbers the touched lines at the cycle's "end" (one register
  walk plus a sort per touched line); the positions that moved drop out of the per-state fast path, so those
  vehicles are renamed on the next cycle through the ordinary rename path: the shared budget per 2 s window, the
  pending / retry rules, never a hand-typed name. A vehicle without a position yet waits (`lineWait`) for the end of
  the cycle. While a long line closes up, two vehicles can show the same `#NN` for a few seconds (renamed in list
  order). Log: `sweep ... lineMoved= lineWait=`.

**Old-vehicle mark** (`old`: Off / Hourglass `⌛` / Star `*` / Word `(old)`):
- The lifespan lives in the model: `metadata.maintenance.lifespan` (`type.d.tl` `record Maintenance`; base `.mdl`
  files, e.g. `vehicle/waggon/univ_1_szap/univ_1_szap.mdl` `lifespan = 36525`; wiki `mdl.md:293`: quarter days at
  the normal calendar speed). The base vehicle window's rule (`base/content/gui/line_vehicle_mgmt/vehicle_util.tl:31-51,
  297-313`): the part bought first (ties: the shorter lifespan), `purchaseTime + lifespan * 1000` game ms; past it the
  window shows no "time remaining". We use exactly that (`Reader.expiry`): game ms against `GAME_TIME.gameTime`, so it
  needs no calendar conversion and agrees with the window whatever the calendar speed (unlike years from
  `getDefaultYearDuration`, docs/findings/gui.md "Vehicle age units"; the purchase year still comes from
  `getCalendarDate`, "Phase 2"). A model without a lifespan (0) is never old.
- Cost: the reader computes each vehicle's expiry and wagon count once and caches them per vehicle while part 1's
  and the last part's purchase times and the part count stay (`reader.wantParts`, only with the mark or the train
  length on; `MAX_CONSISTS` cap). The sweep's "old" input is one compare (`now >= exp`), so ageing never builds a
  string: a vehicle is re-rendered once, when it turns old. Replace gives new purchase times, so a new expiry: the
  mark clears. Since the sweep strategy rework, a confirmed vehicle's expiry also goes into a per-state heap, so the
  vehicle is read again when it turns old, not only by the backstop ("Sweep strategy (2026-10-20)" 4).
- The mark goes at the very end (after the year) and is never cut by the 50-character cap. The word is translated
  by the GUI script and sent with the type words (`words.O`, event op=words; the game script waits for them as for
  "Full word", up to 30 s, then English). `⌛` is in Noto Sans CJK but not in Lato (fontTools 2026-10-20,
  docs/findings/gui.md): the game may show `?`, hence the Star and Word options and a TESTING.md check.

**Train length** (`trainLen`: Off / Wagons `+8` / All units `×9`), RAIL vehicles only (trams are TRAM):
- Wagons counts the parts without power (`Reader.power` 0: wagons, coaches, unpowered trailers), so locomotives,
  power cars and powered multiple-unit cars are not counted; shown when > 0 (a lone loco or an all-powered unit shows
  nothing). All units counts every part of the consist; shown when > 1. `×` is in Lato.
- After the model (`L-0045 | Class 101 +8 (1911)`); a format without the model puts it after the number (`L-0045
  +8`). Never cut by the cap: the model is cut first, as before. A changed consist (part count or a purchase time)
  re-renders the name.

**Fleet register console command** (`bavr_console.lua`, docs/console.md "Our mods' console helpers"):
`ug_require("square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_console.lua").reg()` prints a
`[SQFN] REG` line per vehicle (fleet number, id, letter, the three numbers, line position, model, year, line,
status ours / pending / hand-typed / untouched, old, parts, wagons, name), sorted by letter and number, untouched
last; at most 500 (`.reg(n)` for more) plus a count line; then `REG numbers <letter> next= held= retired=` (numbers
given out and no longer held: sold) and a `REG summary` line. Read-only; it reads the saved state the way the GUI does
(`getEntityForGameScript` + `GAME_SCRIPT.state_native:find(...)`, NativeLuaTable `asTable`), never `get_native`
(docs/findings/game-scripts.md), and the vehicles with the game script's reader.

Fixed on the way: the 50-character cap's loop picked its piece with `isModel and m or l`, which with no model took the
line and cut it into the model's place (Model + line + number with no model and a long line showed the line twice);
`test_text.lua` "render cap without a model".

## Sweep strategy (2026-10-20)

User approved 2026-10-20 ("lower steady-state cost"). The phase 1 / 2 cycle listed every vehicle every 2 s game time
and read each one (`getComponent` + model / line reads, 200 per update): with 2000 vehicles about 1000 component reads
per real second at 1x, 4000 at x4, nearly all unchanged. Now (`bavr_sweep.lua` header; settings and defaults
unchanged):

1. **List check first.** Every cycle lists the ids and diffs them with this Lua state's id set (`rt.mark`: id -> the
   cycle that last listed it; `rt.ring`: the ids in a stable order; no allocation per id, the vanished walk only when
   one is missing). Only new ids are read in full. A vanished id is handled as before (the register read, `Reg.prune`,
   Replace matching through `st.gone`) and every per-state entry of it is dropped (they leaked before). A failed list
   read (`reader.list` nil) is no cycle: before, it came back as an empty list and would have pruned every record.
2. **Work queue.** A read that does not settle a vehicle (renamed: the next cycle sees the name arrive; pending,
   deferred, a duplicate name, waiting for a pass, collected by a pass, no line position yet, going to the depot)
   queues it for the next cycle; settled ones (our name confirmed, hand-typed, untouched, a type switched off, given
   up after `RETRY_MAX`) are read again only by the backstop. Per-line renumbering queues the vehicles whose position
   moved. A **full cycle** (every vehicle) runs when the settings hash changes (the GUI's words), the welcome
   answer this state knows changes (`rt.gen`), an Apply pass collects, and in the first cycle of every Lua state
   (load, settings changed between loads).
3. **Backstop** (what the id list can't show: Replace keeping the id, a new consist, a line change without a line
   setting, an id reused within one cycle, a name cleared by hand): `BACKSTOP` = 50 vehicles per 2 s of game time, a
   rotating cursor over the id set, first in the queue (read even while a rename run carries the rest). 50 instead
   of the suggested 25: it gives the ~80 s for 2000 vehicles named in the brief, at 25 reads per game second
   (40x fewer than before); a vehicle read costs a few microseconds, so about 0.1-0.3 ms per game second. Capped at
   `BACKSTOP_MAX` = 500 per cycle (a long gap).
4. **Expiry heap** (old-vehicle mark only): a confirmed vehicle that is not old yet goes into a min-heap by its
   precomputed expiry; a due expiry starts a cycle at once (even while idle) and queues the vehicle. `MAX_EXP_POP` =
   1000 per cycle, `MAX_HEAP` = 200000 entries (rebuilt from the live expiries beyond).
5. **Line watch** (only with a setting that shows the line: a line format or counting "Per line", `cfg.usesLine`;
   otherwise no line name is read at all): `LINE_RATE` = 32 lines per 2 s game time (`LINE_MAX` 400 per cycle), a
   cursor over `lineSystem.getLinesForPlayer` (`getLines` when missing): `getEntityName` (a changed name queues every
   vehicle this state last read on that line) and `transportVehicleSystem.getLineVehicles` (a vehicle this state last
   read on another line queues itself; fewer known vehicles than listed queues the ones that left). A vanished line
   queues its vehicles. Line names are cached until the watch sees a change; without the watch (the reader has no
   line list, or it failed: `lineErr`) they are re-read once per cycle as before and the backstop catches a rename.
   `getLineVehicles` is read in a game script by Organic Towns (docs/findings/roads.md 2026-10-13);
   `getLinesForPlayer` in a game script is unverified (`TESTING.md` J).
6. **Idle back-off.** A cycle without change doubles the interval (2 -> 4 -> 8 -> 10 s game time, `IDLE_MAX_W` = 5
   windows); any change resets it to 2 s: a new or vanished id, a queued unsettled vehicle, a rename, a register
   write, a line watch hit, an expiry due, a full cycle, the welcome unanswered or a pass due. `Sweep.wake` (the
   welcome answer, the GUI's words) resets it too. The Apply / renumber passes keep their speed: their deferred
   renames keep the interval at 2 s.
7. **Budget carry.** Once this window's rename budget is spent (a deferral), the rest of the queue goes to the next
   cycle unread (not while a pass collects or the untouched vehicles are counted): a 2000-vehicle Apply run reads
   about 2 x the budget + the backstop per cycle instead of every waiting vehicle. The leader (and a claimer) instead
   waits in the scan for the next window, up to `HOLD_MS` per cycle ("Rename lease", sticky lease): about the budget
   + 1 reads per window (`test_strategy.lua` "budget carry").
8. Kept: the lazy state read (the periodic prune read is now every 30 s game time, `PRUNE_MS`), dirty-only writes,
   the rename budget / pending / retries, hand-typed protection, numbers only from a state read in the same update,
   the race guard, pause gating, loop caps. Each Lua state has its own id set, queues, heap and line watch; the
   untouched count for the renumber window is counted over the id set at a cycle's end, only in a cycle built
   with the current answer (`rt.builtGen`), so it is never a partial count.

**Worst-case latency** (game time; n vehicles, L lines; real time is this / the game speed):

| Change | Seen by | Worst case |
|---|---|---|
| Bought (new id) | list diff | next cycle: 2 s active, 10 s idle (+ the rename budget) |
| Sold (id gone) | list diff | the same (pruned, `pruned=` in the log) |
| Replace keeping the id, new consist, reused id, line change without a line setting, name cleared by hand | backstop | n / 25 s + one interval: 2000 -> 80 s (+10 s), 500 -> 20 s, up to 250 vehicles every cycle |
| Line renamed / vehicle moved to another line (line setting on) | line watch | L / 16 s + one interval: up to 32 lines the next cycle (2-10 s), 200 lines about 12.5 s |
| Lifespan passing (old mark on) | expiry heap | the first update after the expiry plus one cycle (within about 1 s) |
| Welcome answer, the GUI's words | event / state read | the next 2 s window |
| Settings changed between loads | full first cycle | as before (budgeted renames) |

**Cost before / after** (`test_sweep.lua` "cost", a settled 2000-vehicle fleet on 2 lines, 60 s game time, fake reader,
Lua 5.4 on the dev Mac): before 46000 vehicle reads, 24 lists, mean 0.118 ms per update (35.4 ms in all); after
1500 reads (the backstop), 6 lists, 2 register reads, mean 0.006 ms per update (1.8 ms in all). With a line format
and 62 lines: the same 1500 reads plus 372 line checks (`getEntityName` + `getLineVehicles`) in 60 s, mean 0.077 ms
per update (the fake's `getLineVehicles` scans every vehicle; the game run measures the real one: SQPERF `lines`).

**Log and SQPERF.** The `sweep` line adds `listNew= listGone= back= queued= full= expDue= carried= lineChecks=
lineHits= listErr= lineErr= iv=` (iv: the current interval in seconds). SQPERF sections inside `step`: `list` (list +
diff), `lines` (the line watch), `scan` (the vehicle reads); counters per kind of read: `insNew`, `insBack`,
`insQueue` (retried / line watch), `insFull`, `carried`.

Tests: `test_strategy.lua` (steady state reads only the backstop, a new vehicle within one idle interval, a sale
pruned and forgotten, the backstop bound for a same-id Replace, line renames only with a line setting, line moves
within one cycle, the watch fallback, the old mark within one window while idle, the back-off, the budget carry,
two Lua states, caps), `test_game.lua` (SQPERF sections / counters, the wake), `test_reader.lua` (lines /
lineVehicles, a failed list is nil), `test_lease.lua` (11 Lua states: the rename lease, "Rename lease (2026-10-20)").

## Rename lease (2026-10-20)

**Why.** The first runs showed `update` in about 11 Lua states ("Sim Pool 1-11"), each with its own module locals.
In `2026-10-20_0539_sqot-sqfn` (a settings change re-rendering 399 numbered vehicles) many states logged
`renamed=10` (budget 10) within the same seconds. That alone does not mean 11x the rate: each sweep line sums every
cycle of that state since its last line (up to 10 s game, `cycles=1..4`), and the lines summed over the run give 398
sends for 398 vehicles to rename (1 hand-typed), `dup=0 race=0`, no vehicle sent twice. With 11 states reading a
stale or concurrent copy, every state would have renamed the same vehicles: the offline model of that (every state
in a tick reads the tick's snapshot, the last write wins) sends 3300 renames for 300 vehicles, 110 per window
(`test_lease.lua`, with the lease taken out). So in that run the game's get / set behaved as serialized and the
shared `win` / `used` held; the game speed is not in the log, so the rate per window can't be read back exactly.
What made the shared budget fragile: a get / set pair is not atomic, any Lua state could spend the window's budget,
so a lost or stale write (seen elsewhere: docs/findings/game-scripts.md, a "once per period" guard stored in the
state fired twice) would let several states spend it in the same window.

**Design** (`bavr_sweep.lua` "The rename lease"). One Lua state at a time sends renames: the one the register names
(`st.lo` = its token, `tostring(rt)`, unique per live Lua state; `st.le` = the game ms the lease ends, `LEASE_MS` =
20 s past the leader's last update in a run; `st.lq` = the lease's epoch, +1 per claim).
- A state about to rename already holds a fresh read (the rename path needs the register), so the lease costs no
  `state:get()`; the settled fleet never reaches it (0 extra reads, 0 writes: `test_game.lua` "state reads").
- No live lease: the state writes a claim (`claims=`, a new epoch) and waits; it renames from the next 2 s window on,
  and only while its reads still name it. Two claims racing: the later write wins, the other state reads that and
  follows. The claim's own window may already be spent by the last leader (a lost write that erased the lease), so
  the new leader starts with the next one.
- A live lease of another state: defer like a spent budget (`follow=`; the rest of that state's queue is carried
  unread, so followers read little during a run).
- The leader counts the window's renames itself (`rt.wW` / `rt.wUsed`) as well as `st.used`, and takes the higher:
  another state's stale write that lowers `st.used` can't raise the rate.
- A new load drops the lease (the first init of the load: "One init per load" below), never a late Lua state of
  the same load. A lease the rule misses (a reload it takes for the same load) can't block for long: it ends by game
  time, at most `LEASE_MS` + `LEASE_MARGIN_MS` = 30 s game time after the load (the save's `le` is at most 20 s past
  the save's game time; offline 31.8 s to the first rename), and each new Lua state starts with an empty "newest
  lease seen" (`rt.lLo` / `lLe` / `lLq`), so it goes by the save's lease alone. Keeping the lease at every load
  was tried (2026-10-20) and dropped: every state of the new load then waits for it and they all claim in the same
  windows when it ends; with stale reads two claims of one epoch can each read themselves as the holder (2 of 30
  seeds of the stale 483-name model went to 20 renames in a window, 0 of 30 with the drop). A new state that got a
  dead state's address as its token (`tostring(rt)`) would hold the lease at once: harmless, only one live state can
  have that token.

**Sticky lease (2026-10-20, after the 08:12Z run).** The 08:12Z session (live log at the time of writing; archived at
the next game start as `2026-10-20_0812_*`; `TESTING.md` K, `HISTORY.md`) re-rendered 483 names (Purchase year set
to Off between loads): the limit held (150 renames in 58 s real, `failed=0 dup=0 race=0`) but renames came from 8
`Sim Pool` threads, with 12 claims in 200 renames, and far below the budget (the game ran at 2x or faster, so
150 / 58 s real is at most ~1.3 renames per game second against 5). Root cause, from the log: each Lua state runs
`update` in only part of the ticks (its sweep lines show `cycles=2` per 10+ s game time; a cycle is at least 4 of its
updates: list, prune, scan, end), and the thread name is not the state (docs/findings/game-scripts.md). The leader
renamed only in the scan of each of its cycles (10, then the rest carried to the next cycle, ~5 s game later), and
its lease ended 10 s past its last rename, so it lapsed between the leader's cycles whenever one ran long; another
state then claimed it, and each claim cost the claimer a whole cycle of its own before its first rename (the claim
deferred like a spent budget). The offline model of that (11 states, each running in ~1/11 of the ticks, half the
reads one write stale) gave 427 / 414 windows for 483 renames (ideal 49), 9-10 senders, 22-27 handovers, and one
window with 20 renames (two states each read themselves as the holder). Fix:
- **Hold in the scan.** When the leader's window budget is spent, or a claim waits for its window, the scan stays at
  that vehicle until the next window (`rt.holdW`) instead of carrying the rest and ending the cycle: a leader that
  runs in only some ticks renames in every window it runs in, not once per cycle. At most `HOLD_MS` = 40 s per cycle
  (then the rest is carried as before, so the list diff, prune and backstop still run during a long run); not while
  a pass collects or the untouched vehicles are counted (those cycles read every vehicle).
- **Renewal in every update of a run**: the leader renews `le` whenever it reaches the rename path (a rename or a
  spent window), not only on a rename; `LEASE_MS` 10 -> 20 s.
- **Margin for the others**: another state takes a lease as ended only `LEASE_MARGIN_MS` = 10 s after `le` (the holder
  itself only until `le`), so a read a few seconds stale never makes a live lease look free.
- **The newest lease seen**: each state keeps the newest lease it read (`rt.lLo` / `lLe` / `lLq`, from every
  register read); a read whose lease is missing (a lost write) or has a lower epoch (a stale snapshot) is not taken
  as "no lease", and the leader writes its lease back when its read lacked it. A claim that the claimer's own next
  read misses no longer makes it claim again.
- Cost: none on a settled fleet (the rename path is not reached); a write per leader update during a run (it writes
  anyway). A new vehicle after a run: the leader (which lists too) renames it under its own lease for 20 s, then the
  first rename waits for a claim window as before.

**Run lines** (`bavr_game.lua`; the 08:12Z run logged `pass progress 0/410 ... 47/410`: `st.ptotal` of an Apply pass
from an earlier session, shown for a re-render). A rename run is an Apply pass (`st.ptotal`, the vehicles it numbered)
or a re-render: a load whose settings hash differs from the one the names were rendered with (`st.rh`, set at a pass
and at such a load; a save from before it re-renders nothing and logs nothing), `st.rb` = the names of ours then. The
state that renames counts its renames into the register (`st.pdone` / `st.rr`, in its write anyway) and logs `pass
progress a/b` or `rerender progress a/b` at most once per `LOG_MS` in all (`st.plog`), only while a < b; the run ends
at a cycle of the state that renamed in it (or a full cycle of any state) in which no vehicle waited for a rename or a
number: one `pass done n=<numbered>` or `rerender done n=<renames sent>` (none when nothing needed one), and the run
fields are cleared. Run fields stored in a save belong to that save's unfinished run, which goes on after a load
(progress `a` keeps counting from the save's, one done line). The only stale case was a save from before the run
fields were cleared at run end (rev 1, before `st.rh`): the load that first sets `st.rh` drops its `ptotal` /
`pdone` / `plog` once.

**One init per load (2026-10-20, after the 19:20Z run).** The 19:20Z load logged two `init` lines (19:20:29Z Sim
Pool 6, 19:21:53Z Sim Pool 5, no "Loading game from file" between): a Lua state whose first update came 84 s game time
after the first state's, past the old 60 s game-time rule (`now - st.boot >= BOOT_MS`). That second "first init" also
dropped the lease and the run fields mid-session (a needless handover, a broken progress line). Game time alone can't
tell a late state from a reload (a reload starts at the save's game time, also at or past the boot stored in it). Now
the run fields are never dropped at load (above), the lease only at a new load, and "same load" = game time did not
go back (`now >= st.boot`) and the wall clock (`os.time`, `env.realTime`, pcall) says the stored first init
(`st.bootT`) is less than `BOOT_REAL_S` = 300 s ago: well above the observed 84 s spread, far below quit-and-reload
after some play. Both mistakes are safe: a reload within 300 s of the first init of the session that saved it skips
its init line and keeps the save's lease (renames wait up to ~30 s game time, above); a state whose first update
comes later than that logs a second init line and drops the live lease (the leader writes it back or another state
claims it: the lost write the lease already tolerates). No wall clock: the old 60 s game-time rule (`BOOT_MS`).

**Result offline** (`test_lease.lua`, 11 runtimes, budget 10; windows from the first to the last rename):

| Model | Before | After |
|---|---|---|
| serial, 300 vehicles, each state in every tick / 50 % / 30 % / 10 % of the ticks | 31 / 35 / 43 / 138 windows, 7 senders at 10 % | 31 / 31 / 33 / 62 windows, 1 sender in all |
| concurrent (every tick's writes but the last lost), 300, 100 % / 50 % / 30 % | 35 / 32 / 51 | 31 / 31 / 37 |
| stale (each state in ~1/11 of the ticks, half the reads one write stale), a 483-name re-render, seeds 1-6 | 427 / 414 windows (seeds 1 / 2), 9-10 senders, 22-27 handovers, a window with 20 renames | 83-98 windows (ideal 49), 1 sender, 0 handovers, at most 10 per window |

At most 10 renames in every 2 s window in every model (also an old copy written back mid-pass; two claims racing);
numbers unique, every name arrives, each vehicle renamed once (serial, stale). What is left between 49 and ~85
windows in the stale model is the leader's own update rate: running in ~1/11 of the ~10 ticks of a window, it runs in
only ~61 % of the windows (1 - (10/11)^10), so ~80 windows is the bound for a strict per-window budget. Closing that
gap would need a leader that may use a missed window's budget later (a token bucket: 20 in one window after an empty
one) or more than one sender; not done (the "10 per 2 s" setting would then hold only on average).

## Later ideas (not built)

- A home town code suffix, and number blocks per town (`B-1201`… for one town's buses).
- Hand-made short names for the base models (a table of `Citaro`-style names, instead of cutting the model name).
- A vehicle-window card: lock / unlock a name, renumber a vehicle.
- Restore the original names (`orig` is recorded) and editable type letters: a v2 window.
- Line Manager Plus's vehicle hover showing the fleet number.
- GUI hint on buy/replace/sell events (unverified events): the GUI script could tell the game script to look at a
  vehicle at once instead of waiting for the next list or the backstop (a later probe).

## Open questions

- The tram default word (no trams in the probe save), and default words in other game languages (`^%D.-%s%d+$`
  must hold for ja / zh / ko too, or we key on `orig` alone).
- Prefix letters editable? mod.json params have no text field, so it would need a v2 window.
- Restore original names: later (v2).

## Phase 0 results so far

- 2026-10-20 (read-only console probe): default names, NAME component present, Carrier enum,
  `getVehicleNames(carrier)` (`docs/findings/lines-vehicles.md` "Default vehicle names and the NAME component").
- 2026-10-20: `makeEntitySetNameCmd` on a vehicle: ok=true, the new name is readable in the callback, kept after
  a save and reload. Helicopters: `metadata.airVehicle.isHelicopter` reads `true` from a script.
- Still open (now `TESTING.md` D and F): does Replace keep the id and name; vehicle-list sorting of `B-0412` /
  `B-1000`; a 40-vehicle rename burst. Destination Displays detection: decided in phase 2 (`getModParams` key).

## Console snippets (phase 0)

Vehicle ids from the 2026-10-20 probe save: road 212817 (`AMO F-15`), ship 212721, train 195844, aircraft 193792.

```lua
local V=212817; print(api.engine.util.getEntityName(V), api.engine.getComponent(V, api.type.ComponentType.NAME)); local t=api.engine.getComponent(V, api.type.ComponentType.TRANSPORT_VEHICLE); print(t.carrier, t.state, t.line, #t.transportVehicleConfig.vehicles, t.transportVehicleConfig.vehicles[1].purchaseTime)
```

```lua
local V=212817; api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(V, "Test B-0412"), function(d, ok) print("SQFN rename ok=", ok) end)
```

```lua
for _, c in ipairs({api.type.enum.Carrier.ROAD, api.type.enum.Carrier.RAIL, api.type.enum.Carrier.TRAM, api.type.enum.Carrier.WATER, api.type.enum.Carrier.AIR}) do local n=api.engine.system.transportVehicleSystem.getVehicleNames(c); print("SQFN", c, #n, n[1], n[#n]) end
```

Read back: `make logs-grep PAT='SQFN|Road Vehicle' ARGS='--session live'`.
