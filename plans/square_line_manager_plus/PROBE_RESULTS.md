# Balance probe, run 1: results (analysed 2026-10-11)

Run by the user 2026-10-10 (no written observations). Log: `probe_run1.log` (216 `[LMPProbe]` lines; full game log
`<TF3_USERDATA>/crash_dump/stdout.txt`, lines 7729-8063). Probe and steps: `PROBE.md`. Verified facts also went to
`docs/findings.md` "Re-sending a vehicle to its own line, departure schedule".

## What was run

| # | gameTime (ms) | Line | Action | Vehicle (state before) | Arg | Track |
|---|---|---|---|---|---|---|
| 1 | 79614000 | Bus Passengers-Hia-LO-1 (4 stops, 4 buses × 8 seats) | Snap | | | until the 2nd Snap |
| 2 | 79619600 | bus | **Send:plan** | 123418 `AT_TERMINAL Loading` stop 3, 0/8 | stop 1 | 33 s (replaced by #3) |
| 3 | 79652800 | bus | **Send:back** | 175083 `EN_ROUTE` → stop 0, **8/8** | stop 3 | 16 s (replaced by #4) |
| 4 | 79668800 | bus | **Send:plan** | 134570 `EN_ROUTE` → stop 2, 7/8 | stop 0 | 7 s (replaced by #5) |
| 5 | 79676000 | bus | **Send:same** | 72235 `EN_ROUTE` → stop 3, **8/8** | stop 3 | ~29 s wall |
| 6 | 79685600 | bus | Snap | | | |
| 7 | 79730400 | bus | Send:back | refused by the probe: `no EN_ROUTE/AT_TERMINAL vehicle with a departure` | | |
| 8 | 79793600 | WC Logs-Hia-Roc-IC-1 (ship, 2 stops, 2 ships) | Snap | | | |
| 9 | 79799200 | ship | **Send:back** | 152112 `EN_ROUTE` → stop 1, **20/20 Logs** | stop 0 | 22 s (Line Manager closed) |

Not run: a train line (PROBE step 5), a bunched line (the bus line was already even), any track for the full 60 s, so
no `after-send` snapshot exists. Speed: 1x for the first ~20 s, then 4x (snapshots 10 s apart are 40 000 ms apart).

Stop positions (bus line), from vehicles standing at them: stop 0 (-43.9,-4226.7), stop 1 (6.9,-4001.7),
stop 2 (-289.5,-4025.1), stop 3 (-646.5,-3891.4).

## Q1: `makeVehicleSetLineCmd` on a vehicle already on the line

**Accepted, 5 of 5:** `SEND plan callback success=true after 0.28s` (0.23-0.37 s for all). The vehicle stays on the
line: every `track` line shows `line=125579` / `line=153284`, never `-1`; `vehicles=4` throughout.

**Buses: the stop index was not applied. Each bus drove on to its next stop in line order and served every stop.**

- #2: `SEND plan: vehicle=123418 state=AT_TERMINAL load=Loading stopIndex=3 -> makeVehicleSetLineCmd(123418, 125579, 1)`
  → `track callback ... state=EN_ROUTE load=None stopIndex=0 (sent to 1)`. It left stop 3 at once and next stood at
  stop 0 (`t=+22s ... v=123418 ... AT_TERMINAL load=WaitForScheduledDeparture stopIndex=0 ... pos=-43.92,-4226.64`),
  departed stop 0 at 79782600 (`deps=[79782600,0,0,0]`), then headed to stop 1: the normal order, 163 s after the
  send (normal section 3→0: 142 s + dwell).
- #3 ("back", does it turn?): `stopIndex=0 -> makeVehicleSetLineCmd(175083, 125579, 3)` → `track callback ...
  stopIndex=0 (sent to 3)`, `toTargetStation` 618 → 656 (moving away from stop 3), then `AT_TERMINAL load=Departing
  stopIndex=0 ... pos=-43.92,-4226.66` and on to stop 1 (`AT_TERMINAL load=Arrived stopIndex=1 ... pos=6.94,-4001.68`).
  **No turn-around**; it kept its direction.
- #4: `stopIndex=2 -> makeVehicleSetLineCmd(134570, 125579, 0)` → `stopIndex=2`, arrived at stop 2
  (`AT_TERMINAL load=Arrived stopIndex=2 ... pos=-289.49,-4025.14`) ~85 s after leaving stop 1 (normal section).
- #5 ("same"): `stopIndex=3 -> (72235, 125579, 3)` → drove to stop 3 (`toTargetStation` 117 → 9), `Arrived`,
  `Unloading`, `Loading`, departed normally. **No reset beyond the history wipe below, no unload outside a stop.**
- The cyclic order of the 4 buses never changed (before: 134570 → 72235 → 123418 → 175083; at 79782600 by the same
  model: 123418@0 → 175083@92 → 134570@185 → 72235@280).

Whether the engine ignores the index for a vehicle already on the line, or routes it along the line through every stop
up to the index, can't be told apart from this run (each bus's next stop was on the way). Either way **a bus can't be
moved forward into a gap**: it keeps its place in the queue.

**Ship (2 stops, #9): the index was applied.** `stopIndex=1 -> makeVehicleSetLineCmd(152112, 153284, 0)` →
`stopIndex=0` at once; the track bent round: positions (-1007,-5982) → (-1067,-6149) → (-1252,-5918), `speed` dipping
to 2.36, `toTargetStation` 899 → 993 → 700. It turned around toward stop 0. Arrival not observed (the Line Manager was
closed 22 s later, which stops the tracker).

**Cargo/passengers aboard: kept.** 175083 `8/8` (#3), 134570 `7/8` (#4), 72235 `8/8` (#5), ship `Logs#12=20/20` (#9)
were unchanged on every track line, and the buses unloaded normally at their next stop (72235: `8/8` → `3/8` → `0/8`
at stop 3, then loaded to `8/8`; 175083 `Departing` stop 0 with `5/8`). Not seen: what the ship does with 20 Logs when it
reaches stop 0, the stop that loads them.

**A vehicle sent while loading departs at once:** 123418 was `AT_TERMINAL Loading` with `0/8` (just unloaded) and left
empty (`track callback ... EN_ROUTE ... Passengers#0=0/8`).

**The command wipes the vehicle's history:** right after #2, `deps=[0,0,0,0] sectionTimes=[0,0,0,0] visited=[]
lastLineStopDeparture=0`, `progress=nil`. Same for every other send. It refills: one `lineStopDepartures` entry per
departure, one `sectionTimes` entry per arrival.

**Re-entry into the progress order** (first departure after the send, which gives `lastDep`): 175083 29.8 s, 72235
41.2 s, 134570 76.8 s, 123418 163 s (game time). But the probe's model also needs line-average `sectionTimes`, and
since all four buses had been re-sent, the line had none: `active=0 T(s)=0` at 79685600-79730400, then
`T(s)=58.40 H(s)=19.47 sectionsComplete=false` at 79775200. Complete `sectionTimes` for a re-sent vehicle take one
round trip (~6.5 game min on this line).

## Q2: WaitForScheduledDeparture and `timeUntilNextScheduledDeparture`

- **`tUntilSched` counts down only while the vehicle is at a stop** (123418 at stop 3: 15.80, 14.80, 10.80, 10.20 over
  ~5.6 s) and is frozen en route (175083 `-1.40`, 134570 `-5.67` in every snapshot while driving).
- **It is set on arrival to (latest departure of another vehicle from that stop + line frequency) − now:**
  - 123418 arrived at stop 3 with `+15.80` at 79614000 → scheduled 79629800; 175083 left stop 3 at `79529400` + 100 s
    = 79629400.
  - 134570 arrived at stop 1 with `+0.60` (≈ 79644800) → 79645400; 72235 left stop 1 at `79544800` + 100 s =
    79644800.
  - 72235 arrived at stop 2 late: `-81.23` → scheduled ≈ 79548800; 175083 left stop 2 at `79447800` + 100 s =
    79547800. The newer departure there (123418's 79544200) had been wiped by send #2, so the engine used the next
    one: **wiping a vehicle's departures also changes its follower's schedule.**
  - With no recorded departure at that stop (all wiped), arrivals start at ≈ 0 (`-1.40`, `-0.40`).
- So the engine keeps a per-stop departure schedule at frequency spacing; before the probe, departures at every stop
  were 93-108 s apart (frequency 100 s), and gap/H was 0.91-1.11. "Ensuring safe distance" is very likely the engine
  holding a vehicle that arrives ahead of that schedule.
- **But the one WAIT observed doesn't fit:** `t=+22s ... v=123418 ... load=WaitForScheduledDeparture ... tUntilDep=7.40
  tUntilSched=-5.60`, `t=+23s WAIT ... tUntilDep=3.40 tUntilSched=-9.60`, departed at `t=+24s`. It held ~8-10 game s
  with `tUntilDep` counting the hold, while `tUntilSched` was already negative (this was right after its own wipe).
  The trigger stays open; one sample at 4x (the 1 s sampler sees every 4 game s) isn't enough.

## Q3: Are the data consistent enough to rank vehicles?

**Yes, for vehicles that haven't been re-sent:**
- Units: `gameTime` and `lineStopDepartures` in ms (`gameTime` +10000 between the 1x snapshots 10 s apart; `since`
  84.60 → 94.60). `sectionTimes`, `tUntil*` in s. `DEP_UNITS_PER_SEC = 1000` is right.
- `lastDep(byDep/byIdx)` agreed in every sample of a vehicle with history (`4/4`, `2/2`, `1/1`, `3/3`).
- Progress advanced exactly with game time (175083: 298.85 → 304.45 over 5.6 s) and the order was stable.
- **`sectionTimes[i]` excludes dwell** (stop i → i+1, departure to arrival, set on arrival). `depDiffs` = section +
  dwell (175083 after its re-send: departure gap 68.60 = `sectionTimes[1]` 58.40 + 10.2 s at stop 1). The index mapping
  is right (section i starts at stop i). Σ`sectionTimes` = T 356.65 s vs a departure-to-departure round trip of 392 s
  (72235) and frequency × n = 400 s: ~10% short, and a vehicle's progress runs on past the next stop's `cum` while it
  dwells, then jumps back on departure (72235: 152.53 at the stop, 149.07 just after leaving).
- `lastLineStopDeparture` is not the latest departure (175083: 79118800 vs latest 79529400) and stays 0 after a wipe:
  don't use it.
- `frequencySec` (`line_util.calculateFrequencySeconds`) is perturbed by wipes: 100 → 109-111 s (bus), 404 → 415 s
  (ship).

**Did re-sending improve spacing?** No, and it couldn't here: the line started even (gap/H 0.99, 0.98, 1.11, 0.91;
the planner said `wouldResend=false` every time before the wipes) and ended about the same (by the pre-send model at
79782600: 1.03, 1.04, 1.07, 0.86). The buses kept their order; the only changes were 123418 leaving stop 3 ~10 s early
and empty, and all four vehicles losing their history.

**Did the planner pick sensible targets?** Before the wipes it correctly saw no bunching. Its picks were still poor:
the "most bunched" vehicle in #2 was one standing at a stop mid-loading. After the wipes it went wrong:
- **H recomputed with n − k:** `active=3 H(s)=119.09` (true ≈ 89) after one wipe, `active=2 H(s)=176.80` after two, so
  gap/H fell to 0.57 for an unchanged gap of 100 s.
- **Incomplete sections:** `T(s)=58.40 H(s)=19.47 sectionsComplete=false` → `wouldResend=true` for a 5.4 s "gap" that
  was really ~90 s. A false positive.

## Other observations

- No `[LineManagerPlus]` errors or warnings in the probe session; all 6 features logged `installed`. Each Line Manager
  open prints engine stack tracebacks with no message, ending in `lmp_capture.lua(63): editedLine` (`p.lineState:old()`)
  via `undo.lua(93)` and `lmp_actions.lua(113)`; they appear in every earlier load of this log too (lines 2208, 3994,
  5017, 7163), so they predate the probe. Harmless so far, but worth a look in LMP (reading `lineState:old()` during a
  render/lazy-state init seems to trigger it).
- `Init streets add proposal error: Construction Not Possible` (06:54:28) is unrelated to the probe.
- Probe bugs (for a run 2): each Send replaces the running track (no track reached 60 s); `stopPos` returned nil for
  bus stops 0 and 1; `getVehicleSimEntitiesCount` returns a table (`total=table: 0x...`).

## Recommendation for Phase 7: don't build Option A as designed

Option A's premise was "re-send the bunched vehicle to a stop in the middle of the largest gap". On road lines that
doesn't happen: the bus keeps its place in the queue. What a re-send does instead is harmful or neutral:
- a vehicle at a stop leaves at once, without loading;
- it erases the vehicle's departures and section times, which (a) blinds our own planner for up to a round trip and
  (b) shifts the engine's own departure schedule for the next vehicle;
- on a 2-stop line it can turn a loaded ship around, with the cargo still aboard (fate at the origin unknown).

And the engine already spaces vehicles: a per-stop departure schedule at line-frequency spacing, with early vehicles
held. The test line was within 0.86-1.11 H without help.

**Recommended:** drop Feature 5 as an action (no `line_balance` re-send button). If a balance feature is still wanted,
make it **read-only**: show each vehicle's gap/H in the Line Manager (e.g. in the colour-dot tooltip or the vehicle
list), so the player can see bunching and fix it by hand. That needs no commands and can't harm a save.

**If the user wants an action anyway (modified design), only after a run 2 confirms it helps:**
- Only lines where the probe showed the index is applied (2-stop lines, ships; trains unknown). Never re-send a road
  vehicle on a line with 3+ stops.
- Only `EN_ROUTE` vehicles that are **empty** (`getVehicleSimEntitiesCount` per cargo = 0), never `AT_TERMINAL`.
- `n` = every vehicle on the line (not `IN_DEPOT`/`GOING_TO_DEPOT`), not just those with a progress; refuse ("not
  enough data yet") if any of them has nil progress (re-sent recently) or if any section has no measured time.
- T from departure-to-departure differences (or `frequency × n`), not Σ`sectionTimes` (10% short, no dwell).
- Act only when the smallest gap < 0.5 H **and** it persists over two samples ≥ 30 s apart (the engine may fix it).
- Cooldown: one action per line per round trip (store the time in GUI memory only), since a re-sent vehicle needs a
  full loop before its data is complete.
- Targets only ahead of the vehicle in line order.

## What the user should check (run 2, if Feature 5 is still wanted)

1. **A genuinely bunched bus line** (two buses nose to tail): Snap for several minutes at 1x. Does the engine pull them
   apart by itself (`WAIT` lines on the follower, gap/H rising)? This decides whether any balance action is needed.
2. **A bus line with 4+ stops: Send to a stop two ahead** (not the next one) and let the track run the full 60 s
   without another click. Does the bus skip the next stop? Settles "index ignored" vs "routed through every stop".
3. **A train line** (PROBE step 5), reversible and loop: does a re-send to a stop behind turn the train?
4. **The ship turn-around with cargo:** let #9 run to stop 0. Are the 20 Logs unloaded at their origin, kept, or lost?
   Does the ship then load more and continue normally?
5. **`WaitForScheduledDeparture`:** a line with "Ensuring safe distance" in a vehicle window, at 1x, to see
   `tUntilSched` and `tUntilDep` at the start of a hold.

Probe fixes before run 2: refuse a new Send while a track runs (or track several), fix `stopPos` for all stops, log
`getVehicleSimEntitiesCount` as a sum, and add a "Send:+2" variant for check 2.
