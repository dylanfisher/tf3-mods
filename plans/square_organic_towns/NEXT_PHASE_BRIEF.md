# Next phase (after the showcase feedback): brief (2026-10-11)

Agreed with the user: run this phase after the first showcase screenshots and feedback are in, and fold their
feedback into it. Each part in a subagent; dev-mod changes in one go.

## 0. Inputs to read first
- The showcase run's `[SQOT_DEV] SHOWCASE` / SUMMARY / CAMERA / DIAG lines and the user's screenshots + feedback.
- Fix already in the repo, not yet verified in game: per-street lane counts in node configs
  (ot_proposal.junctionConns with a lanes table; Driver:buildInfo; ot_engine.templateLanes). It addresses the
  `lane_config_util.cpp:364 GetLaneOffset` assertion seen in pre-checks during the showcase (refusals, not a
  crash). Confirm it's gone from the next log. 2026-10-11: completed and checked offline (every lane index
  validated before sending; root cause and the JP dense stop: PLAN.md 6.2 "Showcase v2").

## 1. Faster showcase (dev mod)
Measured: ~80 s per round of 16 towns, ~5 s per town. ~4 s of it is our own fixed pauses (`SC.PASS_S = 2`
after each of 2 growth passes); ~1 s is command round-trips (0.3–0.4 s each, one in flight). The UpdateSize
command seems to add buildings at once (cap 1110 -> 1285 between passes).
- DONE 2026-10-11 (user: "why would I want to wait"): fixed pauses removed (SC.PASS_S, R.GROW_PASS_S,
  R.FAST_PASS_S = 0); each step still waits for its command callback. No pace setting: fast is the only mode.
- DONE 2026-10-11 (Showcase v2): growth commands for all towns go out as one batch per round (style-town jobs
  first, one after the other); `SHOWCASE ROUND … s=` logs the round time. Still to check: the metrics against
  the paced first run.

## 2. Roundabouts with square_roundabouts (optional dependency)
User wants: when Roundabouts & Interchanges (`mods/square_roundabouts`) is installed, some towns place
roundabouts where appropriate: the less crazy ones (mini/small/medium, 3–4 arms; never magic/interchanges),
mostly in later years (~1960+), planning ahead at junctions likely to become dense.
- Detection: `square_roundabouts_presence.lua` (same pattern other mods use) / pcall ug_require.
- Geometry: reuse `square_roundabouts::/.../square_roundabouts_geometry.lua` (pure) via ug_require rather than
  copying code; alternative: place its street construction by script and connect to the arms.
- DONE 2026-10-11 (offline; in game pending): detection + geometry reuse (`otd_roundabout`, PLAN.md 6.2
  "Roundabouts"), dev button "Roundabout here", showcase town "EU ext roundabout" (step 3), `RB ADOPT` logging.
- **Probe first** (dev button "Roundabout here"): a small 4-arm roundabout at the town junction nearest the
  camera, joined to town streets. Answer: pre-check passes? one-way/non-town ring road types needed? does the
  town adopt the ring and arms and build houses around? red dead-end sign? cost? Log everything.
- Then design rules (only if the probe works): styles EU extension, Nordic, NA suburb, Superblock (not old
  cores, not strict grids); era gate; arterial × arterial crossings at the frontier (reserve the roundabout when
  the area is still empty); occasional mini roundabouts on minor crossings; seeded, rare. Optional: nothing
  changes without the mod. New user-visible strings translated into all 13 languages.

## 3. Also pending
- Build as player OFF test (does it crash? BaseNodeConfig crash cause bisect).
- Growth lookahead setting: user questioned it; recommendation was to remove it (keep Medium). Awaiting answer.
- Mod settings tooltips: user reports they don't show in the mod settings screen; check other mods' tooltips
  there, record in findings, possibly self-explanatory labels.
- Initial towns: Probe C results come from the showcase's Vanilla angle 0/15/45/90 towns.

## 4. Density levers (user asked 2026-10-11: dense sections vs light suburbs) — proposed, awaiting go
The game already densifies by itself (tall core, small houses at the edge in the showcase shots). Levers to test
in a showcase "density row" (same style, one lever changed per town):
- `makeTownCustomDistributionWeightsCmd(town, weights)`: per-town, per-land-use weights over building levels
  (probe K, never run). ot_style profiles already carry `weights` (unused in game).
- `makeTownDevelopAtCmd(pos, developStreets=false, upgradeBuildings=true)`: upgrade buildings at a point — the
  only per-area density lever found (downtown / station / main-street densification).
- Street size: whether a wider town street template gets bigger/denser buildings along it (TF2 behaviour; not
  verified in TF3) — would make our main-street class choice a per-area density lever.
- Land-use mix via per-land-use sizeFactors (res/com/ind), e.g. commercial strips for NA.

## 5. From the settled showcase + roundabout test (2026-10-11, late)
- After game time passed, EU ext roundabout grew to ~3600 and filled completely: the empty mod streets were lag,
  not a defect. Don't "build closer behind houses". Add a showcase "Settle" phase (run game time N minutes, then
  tour). The one-way roundabout was adopted (houses, crosswalks around it); no red signs in the close-up.
- **Crash:** "Roundabout here" (two-way ring, no configs on new nodes, player on) crashed on the 3rd build:
  Engine.h:323 BaseNodeConfig (findings). otd_roundabout must give every new node an engine-pattern config,
  incl. a correct pattern for one-way ring nodes (in-ring -> out-ring, in-ring -> arm, arm -> out-ring; derive
  from a game-made one-way junction via a node dump). The showcase roundabout path too.
- Planner self-collisions: REFUSED partners=ent-20 (two of the plan's own new edges overlap) — fix in the planner.
- Remaining look issues: zig-zag chains and one-end-joined loops.

## 6. Done 2026-10-11 (late), offline; in game: TESTING.md "Showcase v3"
- Roundabout crash: every new node gets a config (two-way ring: engine pattern per segment lanes; one-way ring:
  derived pattern `ot_proposal.junctionConnsDir`, behind the dev toggle "One-way ring: experimental" until a Node
  dump of a Roundabouts & Interchanges ring node verifies it). Invariant tests: no proposal path sends a new node
  without a config. PLAN.md 6.2 "After the settled showcase".
- Planner self-collisions: new edges of one plan never cross / overlap (ot_check.pairConflict in ot_plan,
  selfClearance invariant). Combination refusals (whole refused, every edge fine alone): junction stars
  pre-checked (`DIAGNODE`), the failing star's newest edge pruned (`PRUNE by=star`).
- Look issues: no zig-zag chains, no loops hanging off a stem (selector rules + post-plan check; offline 0 chains,
  1 lasso in 21 towns).
- Town shapes (user's main wish): 8 archetypes (compact, linear, cross, fingers, fan, twin, lens, ridge) picked from
  site / roads / neighbours / style, steering the selector; saved with the plan frame. PLAN.md 6.3, previews in
  `svg/shapes/`.
- Showcase v3: shape row, density row (lean), Settle phase (speed 4, N game months, then the tour), tour shots after
  the camera settled, Node dump.
- Starting angle per region: preRunFn knows the region after all (its config dict is a list of pairs; the probe
  misread it). Main-mod setting "Vanilla town street angles" (Automatic by region / Grid / Mixed / Organic / Game
  default), translated, documented in description.html "Settings".

## 7. Still open (after the next in-game run)
- Verify in game: no crash with configs on every roundabout node; the one-way pattern (Node dump); the shapes'
  outlines after vanilla growth and settle; what DIAGNODE says about the combination refusals; the settle speed
  and the tour's first shot; whether a new EU map's starting towns follow `[SQOT] ANGLE`.
- Build as player OFF test (still pending; the toggle stays).
- Planning time over budget on big towns (EU organic ~17 ms per increment at 700 edges): slice the plan stage if
  frames hitch.
- Dead-end-only joins: a town whose joinable dead ends run out stalls (seen offline).
- Roundabout design rules (section 2) after the probe answers; density levers after the density row.

## 8. User ideas, 2026-10-11 late (showcase v3 run)
- Superblock's big grids look great and distinct.
- **Mixed styles per map**, not "European map = all European dense": each town's style should come from its own
  site and situation, with the region only biasing the odds. Big flat open areas -> sprawling (superblock,
  suburb, wide grids); coastal and mountain/valley towns -> denser, spidery (hug the coast, wind along valleys).
  Implement as a site classifier (flatness/openness, coast, valley, hill, river) feeding style weights per town,
  multiplied by the region's style weights; seeded and saved per town; log style + why.
- One-way roundabout pattern: Node dump of a Roundabouts-mod node showed 5 conns; ours had 4 (missing arm -> both
  ring lanes). Fixed in ot_proposal.junctionConnsDir (fan-out onto one-way targets), tests updated. Still behind
  the dev "experimental" toggle until a build is confirmed.
- DIAGNODE (26 lines): every failing junction includes a `conn:` edge (the joint edge to an existing node), often
  mixing small with main/medium classes; all-small ones too, at 20–28 m shortest edges. Cause still unknown;
  next: node dump of a game-made junction where a medium street meets a small one, and test the joint edge plus
  its new node alone.

## 9. Showcase v3 results (2026-10-11, late) + user requests
- SUMMARY: 30 towns, built 237, refused 1, stopped 0, 0 lane asserts, 3310 mod edges / 1516 adopted / 5945
  houses, 31 s per round. Node dump of a game-made small+medium+medium junction: our engine pattern = the game's
  (8/8), so mixed widths are NOT the cause of the remaining Construction_Not_Possible (98 notPossibleNoCollision).
- Settle 2 months at speed 4 (80 s): buildings unchanged in every town -> far too short; the earlier full fill
  took much longer. Settle needs ~1–2 game years or a building-count target, or forced UpdateSize during settle.
- Density "upgrade" lever (DevelopAt upgradeBuildings at the centre, every round) exploded its town: 4655
  buildings, capacity 40088 vs ~650 / 2600 for the others. Use sparingly / once.
- Tour: the game writes one screenshot per ~2 s and drops requests while busy: dwell 1 s lost half the shots.
  Dwell options now 3/5/10/20 (min 3). tools/ot_shots.py pairs files by mtime second == SHOT line second.
- Looks: Superblock reads well (big rectilinear blocks). Shape row towns (linear/fingers/ridge) are hard to tell
  apart at 1000 m: outskirts are still sawtooth/stepped block chains; shapes need a wider camera (e.g. 1800 m or
  top-down) and stronger steering. Check elongation metrics in game.
- **User: more wide streets in later years** where appropriate (suburbs, superblock, NA grid arterials): street
  hierarchy per style × era — e.g. from ~1950: arterial = large, collector = medium, local = small for NA suburb /
  superblock / NA grid; EU old cores stay small; MED/JP small/xsmall. Wide streets only on through routes
  (arterials connecting to other arterials), not dead-end stubs (the earlier "too wide" complaint was wide stubs).

## 10. Done 2026-10-12 (offline; in game: TESTING.md "Showcase v4"; details PLAN.md 6.2 "Site styles, hierarchy,
stronger shapes, refusals")
- DONE: **style per town from its site** (`ot_site`; section 8): flat open land -> sprawl, coast / hills / valleys
  -> dense, region only biases, era gates; seeded, saved with the frame (`st`), STYLE `styleSource= styleWhy=`.
  Main mod: Street style Automatic acts on every map with the site style (tooltip / description, 13 languages).
- DONE: **street hierarchy by era** (section 9): NA grid / suburb / superblock / ensanche from 1950 large / medium /
  small; wide only on through pieces that meet another street; wide joints at narrow dead ends (`wideJoin`).
- DONE: **visible shapes**: stronger geometry, arm leads, growth front, corner rule (~30 % fewer teeth), linear
  elong 2.7 -> 6.0 (EU extension). Planning sliced over ticks (coroutine, 4 ms).
- DONE: **settle** (dev): years / plateau, real-time cap (default 20 min), optional forced passes, sample lines;
  tour camera 1800 m, shape row top-down at 2500 m.
- DONE (hypothesis, unverified): **refusals**: junction footprint rule + connector turn / length limits; dev
  `DIAGJOINT` variant pre-checks pin the cause if refusals remain.
- DONE: density lever "upgrade" once per town at step 3 (dev), `DENSITY effect` line.
- Still open: all of it in game (next run); one-way ring verification; Build as player OFF; dead-end-only joins
  stall (NA grid from a 90 m vanilla core in the preview); roundabout design rules; density levers beyond the row.

## 11. Street mix, wide lead cap, joint kinks (2026-10-12; details PLAN.md 6.2 "Street mix", "Joint kinks"; in game:
TESTING.md "Showcase v5")
- User: "for higher density roads we build it's important they still mix in some smaller roads, like it makes sense
  that an offshoot to a suburb is a big road, and has smaller offshoots for neighborhoods." Showcase v4: Superblock
  first increment `hier=wide14/stub0/bare0` of 16 (every lattice line was an arterial).
- DONE: late hierarchy lattice (from 1950): NA grid arterials every 6 blocks + collectors every 2, NA suburb every 8
  + 2, the cross axis a collector; NA suburb curves its local streets and plans cul-de-sacs itself; **superblock
  interior** local streets (two along the axis, staggered short cross streets) inside the unchanged 350 x 250
  arterial grid (cell lines alternate arterial / collector).
- DONE: measurable mix: PLAN `mix=L/M/S`, BUILT `mix=` / `townMix=` (% of new length). Offline over 10 increments:
  large 8-19 %, medium 10-33 %, small 52-75 % for NA grid / suburb / superblock / ensanche (superblock was 78-92 %
  large, NA suburb from a vanilla core 32 % large and no collectors). Medium from an empty town still under the
  20-30 % aim.
- DONE: wide lead cap (late styles): arterials at most 1.25 fine blocks beyond the town's junction front, collectors
  one more; shaped towns' arms may still lead at local width.
- DONE (safety net, rule off by default): joint kinks (edge turning > 60 deg at an existing dead end, DIAGJOINT):
  `ot_core.jointIssues`, `opts.jointRule`; a refused increment with kinks is replanned once with the rule before
  halving (`JOINTRULE`); PLAN logs `kinks= jointRule=`. Hard rule always on was tried: it stalled vanilla-core
  growth offline.
- Open: all of it in game; whether kinked joints mostly fail (then turn `ot_select.JOINT_RULE` on, or build a
  straight lead-in first and turn at a new node); medium share; vanilla-core grids still grow as spindly arms
  (dead-end joins only), now at local width.


## 12. Shapes round (2026-10-12; SHAPES_BRIEF; details PLAN.md 6.3 "Shapes round"; in game: TESTING.md "Showcase v5")
- Cause of the round shape row (Showcase v4), found in the log and reproduced offline: the driver's street snapshot
  only held streets within the building extent + 300 m, so arm tips further out were invisible and every increment
  filled near the houses. DONE: `ot_driver.townNetwork` follows the town's connected streets (up to 2.5 km),
  SNAPSHOT `net=`.
- DONE: shape envelope (area-preserving, sized by the town's street length; widened only when it would starve an
  increment), arm fronts for the organic growers (ribbons, no bare spines), cross = an X of 4 arms on 6 spokes.
  Whole town at 10 steps from a round core: linear elong 2.1 -> 5.7, ridge 1.9 -> 4.9, cross arms 3.0 -> 3.5, fan
  side 0.77 -> 0.80, twin drift 0.49 -> 0.75, lens 1.4 -> 2.1; houses (proxy) linear 1.13 -> 1.83.
- DONE: `SHAPE` line per planned increment (streets / houses metrics, envelope, arm share); showcase TOWN / FOCUS
  metrics on the whole network plus `houses=`.
- DONE (dev): lock probe twins (linear, fingers: `SHOWCASE LOCK`), frozen twins (`SHOWCASE FREEZE effect`), a fill
  twin (linear, DevelopAt beside its new streets); Probe C row off (the starting-angle finding); settle forced passes
  on by default, the tour waits for the settle; density upgrade effect logged the round after too (it is a delayed
  growth wave, findings 2026-10-12).
- Open: all of it in game; houses still fill around the game core (~60 % of 600 buildings), so from above a shaped
  town keeps a round centre; twin is a lobe, not two towns; lock design that follows the site (valley walls, slopes,
  coast; user idea, PLAN.md 6.3) waits for the probe and a terrain map; the new-map angle (preRunFn) test.


## 13. Houses onto the arms, deep arms, metropolis, short settle (2026-10-12; details PLAN.md 6.3 "Houses onto the
arms", "Deep arms"; in game: TESTING.md "Showcase v6")
- Showcase v5 (session `2026-10-12_0905_top-up-488838`, HISTORY.md): 31 towns, 290 built, 0 refused. Street shapes
  read (linear elong 3.35, ridge 2.91, fingers 3 arms, cross 4), houses did not (~25 % of our edges with parcels,
  houses elong 1.07-1.48); arms were ladders (spine + stubs); lock probe good (flag sticks, houses build, side
  streets 0-1 vs 33), freeze useless; the fill twin exploded to 7196 buildings and grew round; settle 2 years = 16
  real minutes.
- User (2026-10-12): pull houses onto the arms, deep arms instead of ladders, shorter settle, drop freeze; keep the
  linear-fill result as an opt-in "super dense metropolis".
- Found in the v5 log: `makeTownDevelopAtCmd` resets the town's initial land use capacities to its current
  capacities (target = size factor x current size), which is the whole 12x explosion (findings towns.md).
- DONE (A): lock arm / rim streets of shaped towns by default; dosed fill (2 DevelopAt per build beside new arm /
  rim streets, then the initial capacities restored to <= +15 %, <= 1.3 x the first build's; `ic` saved with the
  frame); FILL / FILL restore / FILL effect lines.
- DONE (B): deep arms: the organic master plan has back rows parallel to arm spokes (1 and 2 block depths) with
  lanes lined up across them, arms sit on spokes, strip cost in arm corridors, arm-line tips chosen together (T's,
  no U-combs). EU extension 10 steps: closed blocks in arms linear 21 -> 41, cross 16 -> 38, fingers 12 -> 34, depth
  1.8-2.3 rows, rungs -> 0, linear elong 4.65 -> 7.30; NA grid unchanged; planning ~1.5x. Young towns that planned
  nothing (2 dead ends, no plan junction in reach) retry with relaxed connectors.
- DONE (C): mod setting "Metropolis growth" (default Off, 13 languages, description Settings + Changelog rev 1): towns
  from ~4000 persons get the v5 fill (12 points per build, no restore) up to 50000.
- DONE (D, dev): settle default "3 grow passes" (no game time; each pass one step further); probe row: plain /
  locked+fill twins of linear and fingers, metropolis twin, DevelopAt flag twins (fill only / streets / upgrade);
  freeze twins dropped; tour dwell 3 s (already the default); ot_shots.py SHOT regex unchanged.
- Open: all of it in game; whether DevelopAt builds at its point (FILL effect near=), whether the reset is immediate
  (the restore reads right after the callbacks), the two DevelopAt flags; lock design that follows the site
  (valley walls, slopes, coast; PLAN.md 6.3) on a terrain map.


## 14. Arms fill first, straight wide streets, one-way rings, metropolis as a city style (2026-10-12; details PLAN.md
6.3 "Showcase v7 round"; in game: TESTING.md "Showcase v7")
- Showcase v6 (session `2026-10-12_1732_sqrl-sqsg`, HISTORY.md): 34 towns, 320 built, 0 refused. The deep arms were
  2-row ladder strips 400-900 m past the built edge with almost no houses; houses stayed in the round core (linear
  houses elong 1.19, ridge 1.53). Cause (LOCK / SHAPE step lines): 18 edges of arm frontage per forced round vs ~50
  new buildings, the arm reach counted junctions (which the strips make themselves), not houses; not the lock (the
  unlocked plain twin had the fewest parcels); the dose rarely ran (`skip=surge`). Style towns turned linear from
  "toward the neighbour town". The roundabout was two-way (one-way behind the experimental toggle).
- User (2026-10-12): long linear offshoots happen too much in every style; arms should fill before they extend; wide
  roads straight (large: long straight thoroughfares, medium: modest curves); the roundabout must be one-way;
  metropolis is a city style, not a setting, with variants; a polycentric big-city style (LA: several dense centres
  divided by lower-density land); keep the green gaps of the Density: control town (meadows enclosed by curving
  streets, not every block filled).
- DONE: arm reach strong only for site-picked linear / ridge / fingers and forced shapes, mild for the rest; the
  neighbour pull 0.6 -> 0.12 x context gain; JP dense / NA suburb / EU organic linear weights down.
- DONE: arms fill first (ot_select ARM_FILL): no piece farther along an arm than its farthest housed street + 2 blocks
  (mild 1.25, >= 120 m); back streets / rungs only beside the housed stretch. Offline (empty arms, no houses ever):
  worst gap 1057 -> 201 m after 10 increments. Logs `armFill=`, `armBuilt=`, `armGap=`.
- DONE: straight wide streets (ot_core.straightWide): large <= 10 / 12 deg (edge / joint), medium <= 25 / 30, else a
  narrower template. Logs `hier=.../bent<n>`, `wideDefl=L/M`.
- DONE: one-way ring by default (dev), engine pattern for wide arms and 4-lane rings (outermost ring lane exits into
  every exit lane, entry lanes fan right -> outer); two-way only as `RB FALLBACK`.
- DONE: metropolis automatic (ot_metro): >= 4000 persons, open >= 0.55, rough <= 0.35 (coast / river / valley: corridor
  from open 0.3), not MED hill, seeded 35 %; variants grid / radial / corridor / oldcore / polycentric by region and
  site; large arterials, variant shape / lock / fill, 4 parks. Setting and its strings removed (old values ignored).
- DONE (foundation of polycentric): from 9000 persons one secondary centre 1.2-1.7 km out on flat dry land (two from
  18000), the twin shape with several seconds grows toward it, the metro fill only within 400 m of a centre, streets
  between centres locked, the fill restores the initial capacities with a looser brake (+40 % per fill, <= 3 x base);
  `METRO step dens=core:a/c1:b between=c`. Dev: `Metropolis: polycentric` forces a centre 0.8-1.0 km out from step 1.
- DONE: green gaps measured (ot_metrics.greenGaps: enclosed open land without buildings, patches >= 1 ha) on SHAPE /
  METRO step / showcase TOWN; green reserves (2-3 seeded meadows beyond the town's edge in organic styles and NA suburb,
  4 parks per metropolis) that the plan grows around.
- Dev showcase: metropolis row (one town per variant) instead of the metropolis twin and the DevelopAt flag twins.
- Next step / not done: polycentric as a real conurbation: secondary centres at a junction of two large straight
  arterials (now: along the axis), their own core style (a small grid or organic core per centre), suburb street
  patterns (NA suburb, larger lots) in the land between, centres added over time (a third from ~30000); the dose
  (2 points, mostly `skip=surge`) is too small to matter, either drop it or dose per housed arm stretch; whether the
  game's own street growth fills the green reserves (no control over it); lock design that follows the site (valley
  walls, coast) on a terrain map; vanilla-core grids still grow from dead ends only.


## 15. Arm towns extend again, town forms, metropolis keeps its layout, lattice-first grids (2026-10-12; details
PLAN.md 6.3 "Showcase v8 round"; in game: TESTING.md "Showcase v8", "Real map test")
- Showcase v7 (session `2026-10-12_1900_sqot-dev`, HISTORY.md): 35 towns, 329 built, 0 refused, 14.7 min, roundS 74.1.
  Met: no empty arms in style towns (armGap <= 223 m), arm gaps <= 282 m, wide streets straight (large <= 6, medium <=
  24 deg), one-way roundabout built (7/7 configs, no fallback), refusals down (notPossibleNoCollision 6). Missed: linear
  / ridge grew round (elong 1.26 / 1.06, houses 1.30 / 1.26); the metropolis row converged (own ~0.10, 1425-1852 edges,
  towns touching); superblock and NA grid hardly showed (own 0.30, superblock 0 % large); polycentric's second centre
  never filled.
- User (2026-10-12): metropolis variants great at first, then all the same shape -> keep their character, sprawl
  longer / wider / fingers; variations per style ("JP dense clustered and radiating vs JP dense sprawling"); keep
  polycentric; superblock should read as superblocks (Chicago grid?); faster showcase; a real-map test plan.
- DONE: strong arms hold their envelope (cause: the envelope relaxation took held-back arm length beside the core, the
  houses filled that first; offline linear 1.21 -> 2.62 / houses 2.19).
- DONE: town forms (`ot_form`): clustered / radiating / sprawling / linear / wide / fingers per town on top of the
  style, from the site-picked shape or a seeded draw x site; saved with the frame (`f`), legacy frames get none; logged.
- DONE: metropolis keeps its layout: every new street locked, 36-edge increments, fill brake +25 % per fill (cause: the
  unbraked fill made the game build ~90 % of the streets itself); radial + radiating form -> fingers on 8 spokes, grid
  + linear / wide form -> that outline.
- DONE: lattice-first superblock / NA grid (late) on a game-made core: the arterial cell frame leads (superblock wide
  share 30 -> 37 %, 1.7 x length offline).
- DONE: fills back to back (one wait per build instead of 12), dose surge window jittered per town.
- DONE (dev): form row (JP dense x 4), metropolis band (~3.6 km apart, forced forms), fewer twins / levers (32 towns),
  TOWN `orient= own= dens= form=`, "Tour all towns" with ALLTOWN lines for the real-map test.
- Next / not done: polycentric as a conurbation (centres at junctions of two straight arterials, per-centre core style,
  suburb patterns between, a third centre from ~30000; v7's c1 stayed empty); forms in normal play unverified (only the
  form row is forced); whether the metropolis brake + lock keeps `own` >= 0.35 in game; Chicago-style alleys for NA
  grid (not attempted); lock design that follows the site (real map test first); vanilla-core grids still join dead
  ends only.


## 16. No empty streets ahead of the houses, metropolis mechanics for the grid styles, Nordic loops, crescents (2026-10-12;
details PLAN.md 6.3 "Showcase v9 round", 3.1 "What you should see"; in game: TESTING.md "Showcase v9")
- Showcase v8 (session `2026-10-12_2129_top-up-530609`, HISTORY.md): 32 towns, 310 built, 0 refused, roundS 27.7 (speed
  target met), settle 72.5 s. Missed: linear / ridge round at the end (TOWN elong 1.22 / 1.43, houses 1.12 / 1.21; the
  SHAPE lines read 1.60-2.06 / 1.62-2.08 during the rounds), metropolis numbers (own 0.23-0.31, grid orth 0.50,
  corridor elong 1.21, polycentric c1 0.5 / ha), form row metrics, NA grid orth 0.43; Density: control green 0 gaps;
  notPossibleNoCollision 11. Shots 1-2 dropped again.
- User (2026-10-12): polycentric builds too many empty streets before the town grows; NA grid slow to look like a grid;
  Nordic not recognisable; keep Control A, superblock, the fingers town's edge row, form radiating, form / metropolis
  options; "the metropolis ideas are best so far, metropolis grid feels like the American grid or suburbs"; EU organic's
  "empty green space and big curve" is interesting.
- Causes: linear rounded after the last build (round 10's growth + the settle's 3 passes with no script increment:
  +350 buildings, +113 game edges around the core); polycentric's 36-edge increments (~2.4 km) far outran ~70 houses a
  round, the twin shape and the NA grid lattice laid frames toward the second centre, no fill gate outside arm shapes;
  NA grid drew a linear shape toward its neighbour, small gated increments, unlocked streets; Nordic was a plain grid;
  shots 1-2 fired during / right after a ~3 s Main Thread stall (the TOWN report) and 0.3 s apart.
- DONE: housed front (`ot_select` HOUSED, `style.housedLead`: NA grid 1.5, NA suburb / ensanche 2, superblock / Nordic
  1, polycentric 1.5 blocks), empty budget (`ot_core`, polycentric 2000 m), PLAN `emptyLen= emptyCap= housedHeld=`.
  Offline polycentric: unhoused length per step 9.6 -> 1.0 km.
- DONE: metropolis mechanics at a smaller scale (`style.mech`, `ot_driver.MECH`): NA grid / NA suburb / ensanche lock
  every new street, 28 edges, dosed fill beside any new street; superblock lock + 30 edges; NA grid shapes compact /
  lens first. PLAN `gridShare=`; offline steps 1-3 gridShare 0.89.
- DONE: Nordic cluster loops (`style.cluster`, ot_grow_grid): curving loops around 190 x 150 m cells, cul-de-sacs into
  the cells, 30 % green cells, 4 meadows, low density, fingers / linear (RESEARCH.md "Nordic towns").
- DONE: crescents around a green (`ot_crescent`, `style.crescents`): EU organic 2, EU extension / MED hill / Nordic 1,
  metropolis 1 park; reserves never overlap. PLAN `crescents=`.
- DONE (dev): settle runs the main mod's normal check after each pass; tour shots wait for steady frames, a 2.5 s
  warm-up and a 2.5 s gap; TOWN `emptyLen= modGrid= crescents=`; preview draws the meadows.
- Option for later (user, metropolis feedback): metropolis-style mechanics (lock every new street + bigger increments +
  fill) at a smaller scale for the other styles too. Tried where cheap: the grid styles (above). Not yet for EU
  organic / extension / MED hill / JP dense: their game-made side streets are part of their look, and locking every
  street would stop the game's lanes between ours; a candidate is "lock only the arterials / spokes" (the metropolis
  radial variant's v7 rule, `MET.lockKeys` with LOCK_ALL off) plus 24-edge increments. Measure with `own=` and the shots.
- Next / not done: the form row (v8 missed every metric: linear +0.13 elong, sprawling not sparser, radiating 1 arm);
  single-loaded edge rows facing open land as a deliberate feature (the fingers town's left side); polycentric's second
  centre as its own small core once the houses reach within ~2 blocks (now it only fills when reached); linear beyond
  ~2 elong in game needs the game's own side streets off the round core to stop (no lock on existing edges without
  rebuilding them); green gaps of the Density: control town (0 in v8); notPossibleNoCollision 6 -> 11.

## 17. Growth-demand trigger: the mod builds in normal play (2026-10-12; details PLAN.md 6.3 "Growth-demand trigger";
in game: TESTING.md "Real map test" item 0)
- Real map + Simulate natural growth (session `2026-10-12_2306_sqot-dev`, 16 towns, 32 simulated years): **0 builds**,
  388 CHECK lines all `why=open`. The game added 682 street edges of its own (0.29 per new building) whatever was free;
  open frontage stayed >= 2x the need (Aldershot open 426 -> ~770, need 83 -> ~320). Findings "At the game's natural
  pace ...". The room trigger never fires in normal play; the showcases only built because their jobs were forced.
- API: no per-town switch for street growth (`developmentActive` stops all growth, `roadDevelopmentLocked` per edge,
  `townDevelopInterval` global, DevelopAt's streets flag no clear effect).
- DONE (offline): growth demand (`ot_assess.demand` / `served`, session ledger of served size factors per town):
  `why=demand` builds when the target grew >= 4 edges' worth since the last build and our own streets' open frontage
  is under the lead (2x the game's open frontage, <= half the built lots); `why=ahead` waits for houses; increments
  sized to the demand in the non-mech styles; demand capped at 2 increments. Own streets = locked + this session's
  builds, counted wherever they are. CHECK `demand= perEdge= ownOpen= ownEdges= lead=`, BUILT `trigger=`. Offline
  (test_demand.lua, 5 seeds): room rule 1 % mod share; demand trigger 39-60 % of new edges, builds every 2-3 checks;
  a stalled town gets one increment, then waits.
- Next: the real-map rerun (TESTING.md item 0: BUILT count, `why=` mix, mod share per town, `ownOpen` vs `lead`,
  the Tour shots). If the share stays low: more lead (`OWN_MATCH` / `OWN_CAP`), lock more of our streets (the
  game then grows only from its own dead ends), a shorter "empty" cooldown. Open: whether our unlocked streets keep
  their ids (a game branch splits an edge: the halves no longer count as ours this session, so `ownOpen` reads low).

## 18. Shore towns (2026-10-12; details PLAN.md 6.3 "Shore towns"; in game: TESTING.md "Real map test" item 11)
- User: "some coastal towns prefer spreading across the coastline, similar to how high real estate can be on the coast
  ... more prevalent on island maps, but lakes also act like this." Before: coast -> style, fan or a straight strip,
  a slight lean, a straight metro corridor; a round lake inside the 600 m disc read as a river.
- DONE (offline): shoreline trace (`ot_terrain.shoreline`: boundary walk both ways, lake / pond / island from a
  closed loop; river only when elongated); site `body= island= shore=`; shape "shore" (along the traced shore's curve,
  depth cap 2-4 blocks, x 0.75 on islands); form "shore" (seeded ~30 % + island / near-water bonuses, strict grids
  less; with the shore-strip shape candidate ~55 % of coast / lake towns, ~80 % on small islands); waterfront
  promenade + row of small blocks (`ot_shore`), streets near the water first (`waterPremium`), dose fill at the
  waterfront, metropolis keeps / gains the shore corridor. Logs STYLE `water=`, SHAPE `shore= shoreFront=`, TERRAIN
  `waterDirs= waterKind=`. Offline: near-water share 0.9-1.0 (clustered ~0.45), shoreline covered 1.6-2x, depth90
  ~110 m (clustered ~560 m); river / pond towns never shore.
- Next: the real-map run on a map with coast, lakes and ideally islands (TESTING.md item 11): trace quality on real
  shores (`stops=`), the share, the promenade built (medium vs small), towns reading as strips along the water.
  Not done: a coast town in the dev showcase (Blank Slate's sea is at the map edge).

## 19. Away from industries (2026-10-12; details PLAN.md 6.3 "Away from industries"; in game: TESTING.md "Real map test"
item 12)
- User: "Is it also possible to make it so cities build away from factories?" -> "At least have a preference away."
- DONE (offline): `ot_industry` (industries within 1.5 km from `getEntitiesWithComponent(INDUSTRY)`, read once per 5 min
  for the whole map; heavy / medium / light by construction file name, unknown = medium + logged once; era weight 0.4
  before 1890 -> 1 from 1920). Applied in the select cost (x (1 + 1.6 pen)), a hold of pieces deep in heavy buffers
  (released step by step when the increment would stay under a third full), the envelope check, the unshaped towns'
  sector lean, the seeded shape axis (turns its arms away) and the DevelopAt dose points. Never a ban.
- Logs: CHECK / STYLE / SHAPE `ind=count/nearest/heavy`, PLAN `indPen=`, SHAPE `indTurned=`, `IND` / `IND unknown`.
- Offline (8 seeds, works 550 m east): share of new streets in the heavy buffer EU organic 0.30 -> 0.03, extension 0.30
  -> 0.10, JP 0.40 -> 0.17, MED hill 0.33 -> 0.08, Nordic 0.35 -> 0.24, NA grid 0.26 -> 0.22; light and pre-1920 in
  between; growth unchanged (JP -9 %); boxed-in towns grow; no industries = identical plans.
- Next: the real-map run (item 12: IND count, `ind=` / `indPen=`, unknown names, shots of towns beside works). Open: the
  read in the game-script state (unverified), grids respond little, no reserved green strip.

## 20. Real map round 2: the mod's turn before the fill, fast growers, fewer shore / Nordic towns, satellites, head start (2026-10-13; details PLAN.md 6.3 "Real map round 2"; in game: TESTING.md "Real map test")
- Run `2026-10-13_0018_top-up-598153` (HISTORY.md): Quick 40 years 194 s, 16 towns, 2473 -> 5990 buildings; 50 BUILT /
  3 FAILED; CHECK demand 59 / open 30; mod share 28 % (small / medium towns 32-95 %, fast towns 8-10 %: Bexley 38 of
  415 new edges in 3 builds); shore form 7 of 16 towns, Nordic 6; no metropolis (Bexley `why=site`); shot 1 dropped.
  Testing: grow towns faster was On (10 GROW lines); the main mod had no industry code yet (game started before it).
- Causes: 4-6 checks per town in 40 years (the driver is busy ~2-4 s per build; fill-year waits all timed out at 15 s);
  the fill before the mod's turn; the demand bank at its 2 x 18 cap in every fast-town check; Braintree's island shore
  strip built out (depth cap 105 m); unexplained: the sim stopped growing each town after the main mod's first dose
  fill restore in it (now logged: SIMGROW stall, FILL effect active=; FILL reactivate if our fill switched it off).
- DONE (dev): fill year = sizes -> main mod's turn for the 6 towns that grew most -> fill -> 4 s wait; clock stops while
  waiting; `res=` / stall lines; tour screenshot primer (`primer=`, `sessionShot=`).
- DONE (main): fast growers (bank 2-6 increments, increments up to 36 edges, "more" re-check after 30 s, picked first);
  shore form ~20 % of sea / lake towns (islands ~40 %); Nordic needs rough + coast outside Nordic maps; rough damped on
  flat town floors; corridor metropolis on a flat valley / river floor; SHAPE `ownShore=`; satellite villages
  (`ot_satellite`, SATELLITE lines, saved site); head start on new maps (HEAD lines); makeInitialStreets documented.
- Next: the rerun (TESTING.md "Real map test" targets: mod share >= 40 % overall and in fast towns, shore ~20-25 %,
  Nordic rare on a UK map, 1-3 satellites, HEAD done before the simulation, shot 1 written). Testing grow **Off**.
  Open: the sim stall's cause (stall line), whether satellites' links get houses, ownShore depth, the industry read in
  game (still unverified), planning hitches (PLAN us up to 262 ms in 5 slices = ~50 ms a slice).

## 21. Real map round 3: character from day one, map edge, character towns, river bridges, organic <-> gridded (2026-10-13; details PLAN.md 6.3 "Real map round 3"; in game: TESTING.md "Real map test")
- Run `2026-10-13_0137_sqot-dev` (HISTORY.md): 16 towns, 59 BUILT / 4 FAILED, CHECK demand 56 / open 17; head start 28
  builds, 256 edges; forms wide / lens 7 of 16 (coast fan -> wide); Axbridge's head start laid ~800 m of empty street to
  the map edge; most towns round blobs, none gridded; 3 towns stayed with development off after later dose fills.
- User: more character from the start (long, skinny, sprawling) within sane limits; never near the map edge; a few
  drastically different secluded towns per map; towns across rivers; more grid in later years and a setting.
- DONE (offline): lead limit 550 m everywhere / 280 m in the head start; head start 2-5 rounds by size / form, arms only
  for armed shapes; map edge margin 400 m + edge-aware shape axis; character towns (top 15 % secluded, extreme sprawling /
  linear / fingers / shore, saved `ch`); fan no longer forces wide, stronger forms; river bridges (ot_bridge; unverified
  in game, all or nothing, BRIDGE lines); era trend + "Town layout" setting (5 steps, default Organic; 13 languages);
  FILL reactivate after every fill (and which command turns it off is logged); demand bank to 2 x 5 increments.
- Next: the real map rerun (TESTING.md targets: towns distinct from the start, 1-2+ character towns, grid share by era,
  no map-edge streets, bridges if any, FILL active fields). Open: whether a script bridge builds at all, its clearance,
  houses on the far bank; how strongly the 280 m head start reads in game; whether the grid look shows in the extension
  rings.

## 22. Neighbour diversity, terrain first, "Starting town size" test (2026-10-13; details PLAN.md 6.3 "Neighbour diversity, terrain first, Starting town size"; in game: TESTING.md "Real map test", "Starting town size test")
- User: "Can we make sure we try not to have the same town style near another town?", then the priority for every later
  round (PLAN.md principle 6): character variation (form / shape / density, gaps) driven by terrain and surroundings
  (slope, valleys, ridges, coast / lake / river, industries, neighbours, map edge), only lightly the regional style id;
  never foreign regional styles just to differ. Where the land is neutral: seeded draw + neighbour diversity.
- User: starting towns are too big for the mod to give them character; easiest option first: a "Starting town size"
  setting that scales the generator's town population factor, as a test of whether cores shrink or only residents.
- DONE (offline): ot_diverse (forms / shapes strong, styles weak, terrain evidence never scaled, saved / character /
  shore / site-shape forms untouched; STYLE nbr= divPen=); hillside contour gain 0.5 -> 0.8; ot_townsize + param
  `starting_town_size` (Game size / Smaller 0.6 / Small 0.35, 13 languages), TOWNSIZE / START / START summary lines, head
  start +1 / +2 rounds and x1.25 / x1.5 edges; tests test_diverse, test_townsize, test_demand (START + scaling).
- Next: TESTING.md "Starting town size test" (two new maps, same seed: Game size vs Small; compare START summaries and
  the tour shots) and in the real map rerun: neighbouring towns differ. Open: whether populationDensity changes the
  generator's cores at all (the menu's map preview generates the towns before preRunFn, files say); if not, the next
  option is shrinking the starting towns at first load (e.g. makeTownUpdateSizeCmd / fewer initial streets) or the
  vanilla "Population" slider; and whether the factor acts at runtime on existing saves.

## 23. Real map round 4: form survives growth, no empty loops, bridges tried, satellite links (2026-10-13; details PLAN.md 6.3 "Real map round 4"; in game: TESTING.md "Real map test")
- Run `2026-10-13_0232_sqot-dev` (HISTORY.md): Testing grow On + dev "Every town grows", 2468 -> 22228 buildings, 355
  BUILT (33 head + 322 demand), mod share 41 % (25-62 % per town), 2 character towns, 4 satellites (+2 dropped
  disconnected), 0 BRIDGE lines, map edge respected. At 1000-3500 buildings the linear / fingers / radiating towns read as
  blobs; Grays' south long empty loops, Harwich's west empty strips; the game calendar stayed ~1900 (no era change).
- Causes: the game's ~60 % of streets from its unlocked core (and the mod's planner) filled the wedges; the demand lead
  (0.5 x built lots) and no cap on the mod's own unhoused length (4-17 km per town); no town read `river` (600 m disc),
  Bootle's river ~1 km out; satellite links not checked against streets; the grid look dropped once the head start saved
  the frame.
- DONE (offline): green wedges (`ot_wedge`, ot_select `style.wedges`: nothing planned beyond the core zone off the arms)
  and wedge frames (locked links between the game's wedge tips, arm gates free; FRAME lines); own empty budget (ot_core
  OWN_EMPTY_*), OWN_CAP 0.35, MAX_LEAD_M 400; bridges toward narrow water within 1.5 km (`narrowWater`), CHANCE 0.75,
  `BRIDGE outcome=none why=` per town; satellite links clear of streets (3 dead ends tried); grid look saved with the
  frame (`gl`). test_bigform: linear houses elong 1.11 -> 4.12 at 10x, wedge share 0.59-0.73 -> 0.19-0.34, fingers 3 arms;
  all towns housed.
- Next: the real map rerun with Testing grow **Off** (TESTING.md targets 24-27: form at 1000+ buildings, FRAME lines, own
  empty <= budget, BRIDGE lines, satellites connected). Open: does the game cross / attach to the locked frame, how much
  leaks through the arm gates, frame joins of two dead ends in game, sprawling towns' gaps (not framed), upward density.

## 24. Real map round 5: industry streets off, satellites built, frames built, towns across the landscape (2026-10-13; details PLAN.md 6.3 "Real map round 5"; in game: TESTING.md "Real map test" 28-33)
- Run `2026-10-13_0342_sqot` (HISTORY.md): Testing grow Off, Quick 264 s, 16 towns, 1992 -> 15517 buildings, 208 builds,
  mod share 34 % (12-69 %); FRAME 15 plans / 12 built (Aylsham's refusal re-sent unchanged); satellites 2 built, 3 seeds
  refused (Collision outside the snapshot); character towns Barrow / Bodmin blobs (920 m from the map edge; Barrow's own
  empty streets at the budget); Middlewich's hill street liked; house clusters next to industries = generator streets.
- User: "do both 1 and 3" (industry streets off by default; satellites more common and built); more spread across the
  landscape, hug coastlines more; keep Middlewich's hill road as a motif.
- DONE (main): "Streets at industries" (ot_indstreets, Off default: `makeInitialStreets = false` in preRunFn, 13
  languages, INDSTREETS line); satellites 55 % from 250 buildings + map quota 2, obstacle-aware site search (edges, tracks,
  constructions, fields), bad sites, 90 s retries, partner kinds logged; frame prune keeps the good links
  (`FRAME outcome=pruned`), excluded links left out later; principle 7 "towns follow the landscape": forms / shapes
  rebalanced (fewer clustered / wide / compact), hillside gain 1.2, one road out -> linear, shore form ~45 % of sea / lake
  towns (islands ~65 %) with longer, shallower strips, lobes along roads / contours; character towns need 1.3 km to the
  map edge; sprawling towns' outer streets dosed; `spread=` (SHAPE, dev ALLTOWN) and `hillRoad=` (SHAPE).
- Offline: test_spread (before/after on 5 synthetic sites: ratio 1.26 -> 1.28, clustered / wide 6 -> 1 of 30), satellite
  obstacles, frame prune in the driver, cramped character towns.
- Next: the real map rerun (TESTING.md 28-33: no clusters at industries with the setting Off and industries working,
  1-3 satellites built, every frame plan built, fewer round towns / more shore strips, hillRoad on hill towns, character
  towns visible). Open: the satellite partners' kinds, whether `makeInitialStreets = false` has side effects, real lobes
  with gaps (only satellites make gaps today), a deliberate climbing hill road.


## 25. Motifs M0: the motif framework, two round-5 dev-test regressions (2026-10-13; details PLAN.md 6.3 "Motifs: the framework"; plan MOTIFS_BRIEF.md; in game: TESTING.md "Real map test" "Motif checks")
- Regressions (dev tests 108/110 after round 5): test_runner "own dead ends": the NA_SUBURB form weight change moved
  the fake town's seeded draw to radiating / cross (one dead end per increment): intended, test rewritten to its intent
  (at most one build per game dead end, stops `empty` with `noConfig`, toggle joins). test_showcase "K refusals": EU
  organic drew wide with green reserves over both dead ends and never planned: main-mod fix, an empty increment plans
  once more without the reserves next to dead ends (ot_core `greensClearOfDeadEnds`, PLAN `greenRelax=`).
- DONE (offline): `ot_motif` registry (kinds with eligible / inputs / style / plan / measure hooks; derived vs drawn),
  seeded 0-2 per town (`MO.MAX`, `SLOT_P` 0.6 / 0.3), neighbour diversity (ot_diverse `motif`), saved on the frame (`mo`;
  old saves none), crescents and the hillside hill road migrated as derived kinds (unchanged), STYLE `motifs=`, MOTIF
  pick / build lines, dev ALLTOWN `motifs=`, dev Town-tab motif picker (forced via startJob `motif`). Tests: test_motif
  (10), test_fixes green relax, dev runner / HUD motif tests. Main 342 / dev 113 green.
- In game: no change in the built towns (no drawn kind yet); MOTIF lines list the derived crescents / hill roads.
- Next (M1, MOTIFS_BRIEF): hill road as a deliberate climb, valley fishbone, harbour crescent, fishing village, each a
  drawn kind with synthetic terrain fixtures and a pattern metric; extend the dev picker (`S.MOTIFS`) and TESTING.md
  "Motif checks" per kind.


## 26. Motifs M1: hill climb, valley fishbone, harbour crescent, fishing village (2026-10-13; details PLAN.md 6.3 "Motifs M1"; plan MOTIFS_BRIEF.md; in game: TESTING.md "Real map test" "Motif checks" 38-42)
- DONE (offline): `ot_motif_land.lua`, four drawn kinds (`MO.IDS` 3-6; `hill_road` stays the derived contour arm),
  groups `land` (climb / fishbone) and `shore` (harbour / village): one per group and town. Eligibility from the terrain
  stats (relief grade, valley axis, the traced shore's bay depth / chord, slope toward the water), size / era / style.
  Plan hooks lay each motif's streets into the master plan (`L.overlay`: crossings become T's, a band beside the line
  and the motif's corridor / zone cleared, cheaper motif pieces); anchors join a line traced from the centre to the
  town's dead end just beyond where it leaves the houses (on the line, or a circular link arc without a kink), with
  plan rebuilds until it has one; ot_select: motif pieces free of the envelope / front / wedge / arm limits and the
  lasso guard (housed front, lead limit, lead depth, own empty budget, map edge, water / grade checks kept), branches
  (ribs, lanes, terrace streets) chosen with the main-line piece at their junction (the game joins only dead ends);
  harbour dose fill on the land side of new crescent streets (FILL `why=motif`); MOTIF build lines with each kind's
  metric; dev picker + 4 entries.
- Offline (test_motif_land, 10 tests, join "deadEnd"): climb on F.terraces 555 m built, +40 m, steepest 6.8 %, 2 of 2
  terraces, corridor clear; fishbone 18 of 20 ribs (9 + 9), spacing 78 m as planned; harbour cover 0.96 of the bay;
  village 3 of 3 parallel streets to the water; eligibility only on fitting fixtures; rules (no crossings, water, grade,
  wide streets, map edge, lead limit, configs / lanes for every new node). Main 352 / dev 113 tests green.
- Next: M2 (ribbon village, village green, crossroads hamlet; MOTIFS_BRIEF "Notes for M2"), then the one in-game run at
  the end of the motif phases (TESTING.md 28-42).

## 27. Motifs M2: ribbon village, village green, crossroads hamlet (2026-10-13; details PLAN.md 6.3 "Motifs M2"; plan MOTIFS_BRIEF.md; in game: TESTING.md "Real map test" "Motif checks" 43-47)
- DONE (offline): `ot_roads.lua` traces each town's country roads (the snapshot's road edges followed outward through
  `E.nodeStreetEdges` / `E.edge`, <= 250 reads, 1.7 km; junctions with their owner town, forks, every road segment) once
  per session (ROADS line, STYLE `roads=`); `ot_motif_road.lua` adds three drawn kinds (`MO.IDS` 7-9; groups `road`
  (ribbon / green) and `hamlet`): the ribbon village (a street 32-45 m beside a country road out of town, 2-4 lanes off
  its far side, road-side dose, locked), the village green (a lens, or a triangle at a road fork, 240-400 m out, linked by
  a stub, the middle kept free, locked, its place kept across plans and sessions) and the crossroads hamlet (the
  satellite seeded beside a crossroads 0.45-1.6 km out, from 120 buildings). Satellites now prefer crossroads and
  farms / light works (heavy / medium still avoided). All towns: ot_select blocks plan pieces across / onto traced
  country roads; withBranches takes a line's branches at its end junction (new junctions only). Country-road nodes are
  never joined (research: PLAN.md 6.3 "Motifs M2"). Dev picker + 3 entries (a forced hamlet seeds at once).
- Offline (test_motif_road, 9 tests, join "deadEnd"): ribbon 365 of 503 m at the setback, 2 of 2 lanes; green lens
  cover 0.91, triangle 1.00, nothing inside, same place in a later session; hamlet 8 of 8 beside the junction; farm sites
  12 of 12; rules incl. no street across a country road and no join at a road node. Main 361 / dev 113 tests green.
- Next: M3 (ring road, station quarter, workers' terraces, cul-de-sac pods; MOTIFS_BRIEF "Notes for M3"), then the one
  in-game run at the end of the motif phases (TESTING.md 28-47).

## 28. Motifs M3: ring road, station quarter, workers' terraces, cul-de-sac pods (2026-10-13; details PLAN.md 6.3 "Motifs M3"; plan MOTIFS_BRIEF.md; in game: TESTING.md "Real map test" "Motif checks" 48-52)
- DONE (offline): `ot_motif_town.lua`, `MO.IDS` 10-13. Ring road (drawn, group ring): a circle around the old core just
  beyond its dead-end streets (radius saved on the frame, `rr`), radial dead ends joined head on by short stubs, arcs only
  where the town's streets / water / roads / the map edge block the circle (never a mid-edge split), the outer districts
  EU extension with a grid look. Station quarter (derived: the gameplay hook): rail passenger stations read through the
  API every 120 s (`E.railStations`, unverified in game), a 3 x 3 / 4 x 4 grid on the forecourt side squared to the station,
  clear of its tracks, with a Bahnhofstrasse from the town; the plan is rebuilt when a town's stations change. Workers'
  terraces (drawn, pre-1920): 3-5 short parallel rows near a light factory (no farms; no heavy / medium works near), free
  of the away-from-industry cost, dosed dense. Cul-de-sac pods (drawn, post-1950): a curving collector with 3-6 plain
  dead-end closes off alternate sides, meadow behind, locked. ot_select: `motifJoin` (several new streets meeting at a
  junction that is still a dead end come together), `motifWait` (a close / row waits for its main line to go on), `indFree`.
  Dev picker + 4 entries. Doc fix: PLAN 2.1 listed an `ot_grow_contour.lua` that never existed.
- Offline (test_motif_town, 11 tests, join "deadEnd"): ring closed (cover 0.99, 36 junctions) on a round core, arcs only
  (cover 0.57) when a street and a lake block it, `rr` round trip; quarter 37 of 40 block sides, squared, clear of the
  tracks; terraces rows square and evenly spaced beside the works' buffer; pods 9 of 12 closes over four styles, every one
  a dead end; rules incl. map edge, lead limit and configs. Main 372 / dev 113 tests green; M1 / M2 numbers unchanged.
- Next: M4 (switchbacks, ridge street, headland street, bridgehead quarter; MOTIFS_BRIEF "Notes for M4"), then the one
  in-game run at the end of the motif phases (TESTING.md 28-52).

## 29. Motifs M4: switchbacks, ridge street, headland street, bridgehead quarter; M3 fixes; era range 1900+ (2026-10-13; details PLAN.md 6.3 "Motifs M4"; plan MOTIFS_BRIEF.md; in game: TESTING.md "Real map test" "Motif checks" 53-58)
- DONE (offline): `ot_motif_relief.lua`, `MO.IDS` 14-17 (`RL.ON`, off in the fixtures; `F.withReliefMotifs`).
  Switchbacks (drawn, group land, relief 6.5-10 % and within 1.35 x maxSlope, never on a crest): legs along the slope at
  ~5 % (L.traceClimb with leg overrides) joined by 80 m hairpin bends placed where their ground stays within maxSlope,
  2-4 bends, dose at the bends, green between the legs. Ridge street (drawn, group land, crest towns): a crest trace
  (highest ground, stops where the crest ends), spurs only down gentle flanks (motifWait), flanks green. Headland street
  (drawn, group shore, a cliff 8 m+ high within 550 m: `ot_terrain.cliff` on the stats): the brink traced along the coast,
  the street 40 m inland of it, lanes inland, dose on the inland side, nothing seaward, no promenade. Bridgehead quarter
  (derived, extra, locked): once the river bridge stands (frame `br` or this session's build: `Driver:bridgeRefresh`,
  plan rebuilt on `bridgeKey`), a 4 x 3/4 grid on the far bank squared to the bridge, its first row the cross street
  continued from its two dead ends (`TW.layGrid`, the station quarter's grid refactored).
- Fixes: `extra` derived kinds take no motif slot (`MO.slotsTaken`; with a station the drawn motifs are now identical);
  motifWait give-up after 6 plans with the line's next piece refused (`SEL.WAIT_GIVEUP`, MOTIF `event=waitGiveUp`).
- Era range 1900+ (user: TF3 starts in 1900 at the earliest; findings towns.md): grid trend 0 to 1910 -> 1 at 1970,
  industry ramp 1910-1945, ensanche from 1920, extension ring from 1915, ring road full to 1940, terraces to 1935 (0 by
  1950); PLAN.md 6.3 "Era range 1900+".
- Offline (test_motif_relief, 9 tests; give-up in test_motif_town): switchbacks 3/3 bends built on a 8.5 % plane (1024
  of 1332 m, climb 77 m), 2 on a shelved 10 % slope, none on a uniform 16 % slope; ridge spine 823 m on the crest (share
  1.00), 10 spurs both sides, spurs only on the gentle half of an uneven ridge; headland 640 / 907 m built 38-41 m from
  the brink, nothing seaward, 10 / 14 lanes, dose inland; bridgehead 29 of 30 sides, all on the far bank, squared, 6
  linked sides (graph-found and plan-given bridge alike); rules (map edge, lead limit, configs). Main 382 / dev 113
  tests green; M1-M3 numbers unchanged (picks with the era change: 1905 ring 15, terraces 33).
- Next: phase F (forest research, MOTIFS_BRIEF "Forest"), then the one in-game run (TESTING.md 28-58).

## 30. Phase F: forest-aware towns (2026-10-13; details PLAN.md 6.3 "Forest-aware towns"; plan MOTIFS_BRIEF.md "Forest"; in game: TESTING.md "Forest checks" 59-62)
- Research (read from files, not verified in a game script; docs/findings/towns.md "Reading trees near a town"): trees are
  `ASSET_GROUP` entities, positions in their `MODEL_INSTANCE_LIST` (fat `transf` / thin `pos`), a tree model has
  `metadata.tree`, groups found with the octree; no forest / ground-material sampler, the generator's forest noise isn't
  reproducible; the game never keeps forest (streets / constructions auto-remove trees; reforestation regrows them).
  Feasible, so built (2a).
- DONE (offline): `ot_forest.lua` (grid, mode, planner measures), `ot_engine.forestReader` (one octree list, model lists
  read with a per-group stride under ~24k reads, sliced), driver stage "forest" after the terrain stats (3 ms per tick,
  once per town per 20 min; `stats.forest`), `style.forest` per plan (hug / clear / none). Hug towns: dense forest costs
  more and waits (relaxed a step at a time, wooded pieces then fill at most half an increment), the forest edge costs a
  little less, dose on the open side. No motif kind (`forest_edge` not needed: the edge premium lays it; see MOTIFS_BRIEF
  notes). Nothing saved, no new node or proposal code (crash rule untouched), no new strings.
- Logs: FOREST (read), STYLE / SHAPE / ALLTOWN `forest=<share>:<mode>`, PLAN `forestMode= forestCut= forestHeld=
  forestRelax=`.
- Offline (test_forest, 14 tests): hug share 0.80 (EU organic small, 1900) -> 0.20 (1990), grids 0.10, metropolis 0;
  160 m clearings: forestCut EU organic 0.17 vs 0.53 clear, MED 0.23 / 0.53, JP 0.10 / 0.49, NA grid 0.19 / 0.61, Nordic
  (440 m clearings) 0.21 / 0.40; reach along the clearings as far as the clear town; forest on one side 0.02 vs 0.31;
  boxed in: 51-56 % of the edges (about half the pace per increment), never empty; clear / none identical to before.
  Main 396 / dev 113 tests green.
- Next: the one in-game run (TESTING.md 28-62), then the later ideas (MOTIFS_BRIEF "Other ideas").

## 31. Later-ideas phase: upward density, protected meadows, tree-lined entries, polycentric next steps (2026-10-13; details PLAN.md 6.3 "Later ideas"; plan MOTIFS_BRIEF.md "Other ideas"; in game: TESTING.md "Final test: all phases")
- DONE (offline): **upward density** (`ot_upward`, driver `upwardDecide` / `upwardStart` / `upwardEffect`): towns from 1500
  buildings (or 700+ with 3 held demand plans) build a demand increment cut by 0.25-0.5 and get DevelopAt(point, false,
  true) at 3 core points along main streets where houses stand, every 180-300 s, restored exactly (`UP.EXTRA` 0: no target
  rise), capped at 1.6 x the base initial capacity; also after an empty plan; never a metropolis / head start. Logs UPWARD,
  UPWARD effect `perBuilding=`, PLAN `upCut=`.
- DONE: **protected meadows** (`ot_meadow`): sprawling towns without arms and unarmed character towns keep meadow sectors
  (the middle 45 % of the gaps >= 70 deg between their lobes) beyond the core zone free of the mod's pieces, and locked
  meadow frames link the game's tips there (ot_wedge.frameStreets `accept`, no tails). Logs MEADOW, FRAME `kind=meadow`,
  PLAN `meadowHeld=`.
- DONE (town side only): **tree-lined entries** (`ot_entry`, ot_proposal `decor`, ot_engine `edgeDecorations`): a seeded
  share of towns builds its new streets along a country road's first 320 m out of town (and wide ones at its entry) with
  the base `town_*_trees` template and its tree rows; a refusal re-sends without them, 2 refusals switch them off. The
  country roads themselves: not safe (never rebuilt), skipped. Logs ENTRY, SEND `trees=`, PLAN `trees=`.
- DONE: **polycentric next steps** (ot_metro, `ot_poly`): centres at country-road junctions in range, a third centre from
  30000 persons (`METRO event=centreAdded`), per-centre core kind (grid / the plan's pattern, seeded by region) with a
  3x3 / 4x4 grid core laid into the master plan, built as the houses reach it (housed front + polycentric empty budget).
  METRO `at=..:src:core`, METRO step `cores=`.
- Not done: reshape starting towns (waits on the Starting town size test); suburb patterns between polycentric centres.
- Offline: main 410 / dev 113 tests green (test_driver upward / entry, test_bigform upward model + meadows, test_later).
  Upward model: mod edges -20 %, r90 -2..-7 % at 10x (the cut; upgrades assumed); meadows: meadow share 0.29 -> 0.18 mean
  at 10x (4 towns), all housed.
- Next: the one in-game run, TESTING.md "Final test: all phases" (everything since session `2026-10-13_0342_sqot`). Run 2026-10-13 (session `2026-10-13_0856_sqot-dev`): results in HISTORY.md, fixes in 32.


## 32. Final-test round: virtual roads, motifs on real terrain, peninsula tip, forest, station back, coast strips (2026-10-13; details PLAN.md 6.3 "Final-test round"; results of the final test: HISTORY.md; in game: TESTING.md "Final-test round test")
- Evidence: the final all-phases test (session `2026-10-13_0856_sqot-dev`): clean (no crash, no mod error), satellites
  (7), frames (24), 2 river bridges + their quarters, station read, tree read, INDSTREETS all worked. Broken / weak: no
  country roads (`ROADS roads=0` everywhere), 2 drawn motifs in 16 towns, forest share 0.01-0.08 on a wooded map, the
  station quarter facing away built nothing, the shore towns read as normal towns, PLAN up to ~144 ms per slice.
- DONE: **real country roads found**: the earlier maps (makeInitialStreets true) have dirt country roads (tour shots), the
  final test's map (Streets at industries Off = makeInitialStreets false) had none: that switch apparently drops the
  generator's roads between towns too (findings towns.md). `SH.exits` missed the roads because they join at the town's
  outer street node beyond the houses' extent (EXIT_PAD 150 m now); the driver reads the road edges wide around the
  town (`ot_engine.roadEdges`, template `country` flag), ROADS `wide=`. Decided (user, 2026-10-13): "Streets at industries"
  now defaults to Game default (keeps the roads between towns; tooltip unchanged, description notes Off's side effect).
- DONE: **virtual roads** (`ot_roads.virtual`, driver `countryRoads`): no road edge near a town -> 2-3 roads traced over
  the terrain toward the nearest neighbour towns (else the land's / seeded headings); the ribbon village runs on the line
  (`off=0`), the village green forks between two, tree-lined entries along their first 320 m from the town's edge;
  no hamlet (no real crossroads). ROADS line: `snapEdges= nonTown= templates= traced= virtual=`.
- DONE: **motif pick / eligibility on real terrain**: crescents take no slot (`free`), SLOT_P 0.9 / 0.4 x best / 0.4,
  MIN_SCORE 0.1; hill climb from grade 0.012 (full 0.035), switchbacks 0.04-0.07, soft valley / ridge (both sides 4+ m,
  ot_motif_land valleyScore / ridgeScore; also for the fishbone / ridge geometry), harbour to 650 m / bay ratio 0.08,
  fishing village to 550 m / grade 0.022-0.05 / 75 deg, headland cliff 6-20 m within 700 m; every kind returns a why;
  debug `MOTIF event=elig free= terrain= kinds=` per town. The hill climb's line falls back to tighter smoothing when the
  smooth line is steeper than its max grade (Wirksworth: grade 0.135).
- DONE: **peninsula tip** (`ot_motif_point`, MO.IDS 18, group point, locked `mpt`): the spit found once per town in the
  terrain stage (16 rays, water both sides within 300 m, neck >= 200 m; TERRAIN `spit=`), a spine re-centred along it to
  short of the tip, 2-4 dead-end lanes at the tip, the neck kept free of the plan's other streets, dose beside it.
- DONE: **forest** LIGHT 25 -> 12, DENSE 90 -> 36 trees/ha, LIGHT at least 1.5 x one sampled tree (stride).
- DONE: **station quarter** on a station facing away: on its back (the town side, beyond its box + 20 m off the tracks),
  linked to the town (`side=back`; `SQ.FLIP_AWAY`).
- DONE: **coast strips**: shore towns from 600 m of water (ot_site SHORE_DIST 450 -> 600, coast candidates 620,
  waterfront 600), SHORE_P 0.34 + 0.16 within 400 m, SHORE_GAIN 0.7; shore geometry ka 4.2, kb 0.32, cf 2.6, depth cap
  240 m; the wedge rule now covers shore towns (inland beyond the depth cap, off the link, is a wedge; frames chain the
  inland tips).
- DONE: **mountain roads more often**: the hillside contour shape from grade 0.028 (was 0.04), gain 1.4, soft valley /
  ridge shape candidates (6 m, 1.5 x).
- DONE: the master plan **yields** between its grower, the motif hooks and the promenade (driver slice).
- Offline: main 420 / dev 113 tests green (new test_motif_point, test_motif_env, virtual-roads, forest calibration,
  shore wedge, station back tests; old expectations updated: SLOT_P, shore shares, the away station).
- Risks: the tree-lined entries go out for the first time (fallback / off after 2 refusals); virtual-road ribbons may run
  long empty streets toward a neighbour (housed front + lead limit still apply); the shore wedge may starve a shore
  town whose strip is blocked; motif counts offline ~90 % of terrain sites (may be too many: the elig lines decide).
- Next: TESTING.md "Final-test round test".

## 33. Hang fix: Henley-on-Thames' head-start round 2 froze the game (2026-10-13; evidence `2026-10-13_1848_sqot`; in game: TESTING.md "Hang fix check")
- Evidence: a new European hilly map, Streets at industries Game default. Henley-on-Thames (town 66049; linear hillside
  character town on a steep lake shore; motifs fishing_village (saved) + crescent + hill_road, forest hug) logged its
  round-2 `SNAPSHOT` and then only the watchdog's `Possible hang detected` for ~80 s until the game quit
  (`crash_dump/error.json` type hang, no stack; RAM flat at 7.7 GB, so the loop kept nothing it allocated). Round 1's
  PLAN took `us=360284 slices=5` (one fishing-village overlay alone ~110 ms offline).
- Not reproduced offline: ~1,000 fuzz plans (Henley's shape / motifs / saved frame / round-1 link street built, country
  roads in the graph, every motif kind x 5 styles x 6 forms, a 2 m quantised noisy sampler, NaN / endless coordinate
  traps on the sampler) all ended within 9e7 VM instructions with no bad coordinate. So the exact loop isn't known.
  Leading candidates: (a) a NaN / endless coordinate handed to `api.engine.terrain.getHeightAt` / `isOnWater`
  (a NaN that came back would have raised "table index is NaN" in the sampler's cache, which wasn't logged, so the engine
  call itself may have spun); (b) a Lua step / cell loop fed an endless coordinate, extent or zero step (several existed:
  `for cx = floor(-inf), ...` in every spatial index / query, `while span <= 0`, the organic ring loop, `resample` with
  step 0, `clearance` step 0).
- DONE: **plan hang guard** (ot_driver `D.guardOn` / `D.guard`, `PLAN_GUARD`): a debug count hook (every 20,000 VM
  instructions) on the plan coroutine ends a slice over `PLAN_HANG_US` 1.5 s or a plan over `PLAN_TOTAL_US` 4 s with
  `WARN stage=plan msg=planHang us= slices= err=<file:line<fn|...>>` (the innermost mod frames: the loop's location),
  the town finishes `fail` (why `planHang`). Every other job stage runs under the same hook (`STAGE_HANG_US` 4 s;
  `ERROR stage=<stage> err=planHang:...`). A plan coroutine error no longer re-plans in one go in the same tick (it
  finishes `fail`). INIT `hangGuard=on|off` says whether the game's Lua has `debug.sethook`.
- DONE: **engine sampler** (ot_engine.sampler): NaN / infinite / beyond 1e6 m coordinates never reach the terrain API
  (height 0, dry). `E.streets` capped at 6,000 edges and guarded against a bad centre.
- DONE: **loop caps** in the planning path: `G.LOOP_CAP` 10,000 on every step / walk loop of the motifs (land, relief,
  road, point, town: the anchors walk, the climb / fishbone / harbour / switchback / ridge / headland / bridgehead /
  ribbon / tip / pods / closes loops); `G.cellRange` (finite coordinates, at most 4,096 cells) for every segment index
  (motif lines, shore lines, country-road segments in ot_select / ot_motif_road, satellite obstacles, shore data); graph
  queries (nodesNear / edgesNear / eachNear / nearestNode) skip bad coordinates and scan all items for huge boxes;
  `resample` (zero / NaN step, at most 20,000 pieces), `fillet` (step 0), `clearance` / `shoreline` (step 0),
  forest `pen` / `cutShare` (2,000 samples per segment), the organic grower (`while span <= 0` -> modulo, rings <= 64,
  extent <= 8 km, ring spacing > 1 m), the grid grower (extent <= 8 km, block >= 10 m), ot_core's master plan extent <= 6 km
  (a far stray node), ot_select's greedy loop (`maxEdges x 4 + 64` rounds, report `iterCap`), prune (passes),
  the shore rung loop (zero spacing).
- DONE: **slice budget**: the driver's yield now also runs inside ot_select's greedy loop (every 4 rounds), ot_plan's street
  loop (every 4 streets), the organic master plan (per spoke / ring / cell) and the motif overlays (every 64 plan pieces,
  `L.yieldFn` set by `MO.applyPlan`, only inside a coroutine); the overlays reject far pieces / points by the line's box
  (Henley-like fishing village master plan 147 -> 66 ms offline; worst offline slice 115 -> 15 ms; the greenRelax rounds
  no longer run inside a pcall, so yielding there works on any Lua).
- DONE (loop audit, 2026-10-13): START rows read the two whole-map maps once (`Driver:mapReads`, shared for 0.5 s, also
  for CHECK and the dev tour) and skip the town network, at most 250 ms (`START summary skipped= us=`); the town network
  stops after 50 ms; the forest reader resumes inside a big group every 256 reads.
- Tests: test_hang.lua (5: every guard under an instruction cap), test_driver.lua (3: an endless plan -> WARN planHang +
  fail, D.guard, the trace text), test_forest.lua (the group resume). Main 428 / dev 113 green (the dev showcase test with
  the 3 ms-per-read fake clock turns the guard off: its fake time would pass PLAN_HANG_US).
- Next: TESTING.md "Hang fix check".

## 34. Landscape names: real town names fitted to the site, industries follow, landscape stop names, dev test stops (2026-10-13; details PLAN.md 6.3 "Landscape names and stop names"; in game: TESTING.md "Landscape names test", "Landscape stop names")
- User-approved design (the "middle option"): on a new map each town gets a real name from the game's own active list
  that fits its site; plain towns keep theirs; the one composition: "Little X" for a small town next to a much bigger one.
- DONE: `ot_names.lua` (pure): the 18 base lists, classifier rules per language, pool, town tags, assignment, satellite
  composer, industry prefix renames, stop themes / names. Driver names phase before the head start (load -> classify ->
  survey (the head start's own terrain / forest stages, so nothing is read twice) -> assign -> rename -> industries;
  NAMES / NAME lines), the saved done flag `nm` + list folder `nd` (EV_NAMES), the engine reads (E.townList, E.language,
  E.setName, E.industryNames, E.streetList, the stop reads).
- DONE: landscape stop names: handleEvent queues new player Road Stops (onPostBuildProposal, ot_saved `sq`, EV_STOPS
  drains), the driver names one per 0.5 s from its spot (STOPNAME line); `Driver:addDevStops` for the dev tool's stops.
- DONE: setting "Town and stop names" (Landscape names / Game names), 13 languages; description Settings + Changelog.
- DONE: dev mod "Place test stops (named)" (Town tab): one curbside Road Stop per theme the town offers on script-chosen
  town street edges, named through the main driver (TESTSTOP + STOPNAME lines).
- Tests: test_names.lua (classifier per language incl. the real base lists, assignment, satellites, industries, saved
  queue, stop themes, the driver's names phase and stop naming against a fake engine).
- Risks: `ug_require "::/names/..."` from the game-script state and `api.util.getLanguage()` are unverified (the folder
  falls back to the town names' match; a failed load ends with `why=listLoad`); the engine may rename industries itself
  (counted, then skipped); script-built stops are a first (dev only).
- Next: TESTING.md "Landscape names test", "Landscape stop names" (done: run `2026-10-13_2113_sqot-dev`, HISTORY.md; the stop
  names reworked in 36).

## 35. Forest / gaps / bridges round: forest by plot depth, forest lanes, gaps, empty streets, motifs that build, ships, industry mix (2026-10-13; plan ROUND_FOREST_BRIEF.md; details PLAN.md 6.3 "Forest / gaps / bridges round"; in game: TESTING.md "Forest / gaps / bridges round test")
- Evidence: run `2026-10-13_1945_sqot-dev` (Quick 40 years, 21 towns, tour shots) and the user's notes ("building around
  forests is really cool, let's keep pushing this"), the user's bridge test (a low bridge cuts a ship lane).
- DONE R1: corridor measure (lots to 36 m + the band beyond), edge premium only one lot depth off the trees, dose to lot
  depth, metre cap on relaxed wooded pieces + a clearing budget per town and decade, grid re-read after 6 builds / 80
  edges, stride bias fixed, `slices=` on empty PLAN lines, CHECK split over two ticks. Logs PLAN `forestLot=
  forestBudget=`, FOREST `renew=`, CHECK `slices= sliceUs=`.
- DONE R2: forest lanes (`ot_lane`): locked era country lanes through forest wooded on both sides, ~1 in 3 (hug more),
  4 per town; FORESTLANE lines, PLAN `lanes=`; dev "Forest lane test" (LANETEST). Barrier decorations: not built.
- DONE R3: gaps (`ot_gap`): 150-300 m short of the halfway line, twins' main roads to the line, never past it /
  another town's land; PLAN `gapHeld= gaps=`.
- DONE R4: own empty dead ends retired after 4 empty snapshots (tighter own empty base for those towns), no empty loops
  in organic styles; PLAN `retired= emptyLoopHeld=`. Tisbury / Stotfold analysed (PLAN 6.3).
- DONE R5: motif fallback to the next eligible kind (`MOTIF event=fallback`), hamlet -> normal satellite search
  (`hamletFallback`), wide peninsula pass (`spit=..w`).
- DONE R6: ship-aware bridges: ship line stops on the crossing's water body (flood fill) = path -> deck 11 m over the water
  level or no bridge; wide water (>= 45 m, proxy) = navigable -> high when it fits; narrow preferred. BRIDGE `ship=
  shipWhy= deck= clearance=`, SHIPS line. Research: no navigability or ship path readable (PLAN 6.3, docs/findings/roads.md).
- DONE R7: SIMGROW per-era split (`mix=era`); dev "Industrial satellite probe" (SATIND). Not done: the optional dose
  away from the industrial district centre.
- Tests: main 471 / dev 118 green.
- Next: TESTING.md "Forest / gaps / bridges round test" (done: run `2026-10-13_2113_sqot-dev`, HISTORY.md; follow-up 36).

## 36. Round after the names run: unique stop names, lanes ahead, forest lanes on through streets, Brentwood's forest, Works towns (2026-10-13; details PLAN.md 6.3 "Round after the names run"; in game: TESTING.md "Round after names run")
- Evidence: run `2026-10-13_2113_sqot-dev` (16 towns, SIMGROW 40 years, shots s3 Brentwood / s8 Henley-in-Arden) and the
  user's notes; the forest round's test results in HISTORY.md. Findings recorded: towns.md (renames / getLanguage /
  indEngine=0, a 10 / 10 / 200 town grows ~93 % industrial, country lanes in town proposals, the game's growth into
  forest), roads.md (ship read works, water level read failed, a high bridge failed "Place on Land").
- DONE phase 1, **unique stop names** (`ot_stopname`): generic per theme x specific from the spot (toward a neighbour
  town, trees by species from the forest read's model names, works / quarry / farm, the theme's features, compass,
  height, the own town; Russian size / age pairs, en / usa Old / New) in 14 classifier languages; real list names
  first; unique map-wide (E.mapStopNames + this session's); industry-named stops kept; STOPNAME `kind= gen= uniq=`.
  500 stops per language: 0 duplicates.
- DONE phase 2, **Henley's stray country roads** = a 6-edge forest lane over a back-row grid (`bk1:2:L1#3`, dev SIMGROW).
  Lanes now one stretch of one plan line, no block-interior lines, town streets at both ends, 2+ edges, 60-400 m.
  **Lanes ahead** (`ot_lead`): a seeded 30 % of young towns (quota) lay one locked country lane 400-1000 m out toward a
  neighbour / satellite / axis, gaps / owner / margin / water / grade / roads respected, a town-street T or ribbon at
  its end for the game to grow on; LEADLANE lines; saved `ld`.
- DONE phase 3, **Brentwood**: the game built ~3 of 4 of its streets (x9.6 forced growth; the mod's plans blocked by the
  game's streets, its own empty budget and a 2 ha budget spent in the head start that never came back; the open meadow
  inside the map margin). Hug towns lock their forest-facing streets (the game hangs none of its own off them); the
  clearing budget opens a window per decade or 1.5x growth, follows the tier, is spent at the build.
- DONE phase 4, **forest lanes**: they did trigger (11 `[SQOT_DEV]` lines: the dev runner's prefix), but hug towns held
  the pieces a lane needs: a held crossing now comes as a bundle (ot_select laneBundle, seeded per line); the dev
  "Forest lane test" finds its town itself (dry runs by forest share, LANETEST pick).
- DONE phase 5, **Works** (`ot_works`): new maps only, >= 300 buildings, seeded 35 %, one per 8 towns (1-3), never a
  character or Works town; site 0.8-1.5 km (harbour / rail / across water best), name per language, E.createTown
  (10 / 10 / 200) + one fill, then a link road at the next demand build (country middle, both ends joined); WORKS
  lines; saved `wk` / `wp`; save-safe (a normal town). No new setting, no new strings.
- Also: CHECK `parts=` (the slow read of 15-62 ms CHECK slices); description Features / Changelog.
- Tests: main 494 / dev 119 green (test_stopname, test_lead, test_works new; test_lane, test_forest, test_names,
  test_demand, dev test_runner extended).
- Next: TESTING.md "Round after names run" (done: run `2026-10-13_2240_sqot-dev`, HISTORY.md; follow-up 37).

## 37. Round after the 2240 run: unique stop names map-wide, industry cues, housed lane ends, Works in the sim, keep-clear zones (2026-10-13; details PLAN.md 6.3 "Round after the 2240 run"; in game: TESTING.md "Round after the 2240 run")
- Evidence: run `2026-10-13_2240_sqot-dev` (new European map, 12 stops, SIMGROW 40 years, shots s0 / s9 / s15) and the
  user's notes; results HISTORY.md. Findings: towns.md (lane far ends unhoused, the game surrounds a farm, the industry
  listing verified).
- DONE stop names: live map-wide used set (the 60 s cache missed "The Grove"), composed names first (real / stand-alone
  last, once), `why=noUnique` instead of fallback themes; richer parts in 14 languages (field names, landmarks, lake
  words, Old / New / Little / Great); 300 mixed stops: 0 duplicates.
- DONE industry cue: the industry theme first within 350 m ("Crop Farm Gate", "Works Road", "Quarry Lane", by kind);
  new player stations within 400 m of an industry and nearer to it than the centre: "<Town> Quarry / Works / Docks" or
  "<Industry> Halt".
- DONE long offshoots: the lead lanes' far ends (the only ones built: Tickhill, Verwood) stayed unhoused; the ribbon end
  at most 120 m, ends must be joined (`endJoined=`), a DevelopAt dose at the far end (`why=leadEnd`); towns of 3+ arms
  start a new arm only half a lead out while another runs ahead unhoused (`armWait=`).
- DONE Works: the dev build round's drivers lacked `newMap` (every `notNewMap`, the shared state then muted the main
  driver); they inherit it now and log as `[SQOT]`.
- DONE keep-clear zones: research (files): only field industries grow, into slots up to ~380 m (farms) / ~220-300 m
  (mines, pits, quarries) from the origin, a colliding slot is skipped silently; the industry read now reaches the
  town's radius + 900 m (Budleigh Salterton's farm was beyond 1500 m: `ind=0`); hard zones (max footprint + 40 m) no
  mod piece enters, doses avoid, streets beside them locked; PLAN `zones= zoneHeld= zoneLock=`, `REFUSED why=industryZone`.
- Tests: main 502 / dev 120 green.
- Next: TESTING.md "Round after the 2240 run".

## 38. Round after the 2355 run: districts, Works by a factory, coastal huggers, bridges, squeezed towns, street-aware stop names, density (2026-10-14; details PLAN.md 6.3 "Round after the 2355 run"; in game: TESTING.md "Round after the 2355 run")
- Evidence: run `2026-10-13_2355_sqot` (results HISTORY.md), BASELINE_VANILLA.md, the user's notes.
- DONE phase 1, **district towns** (`ot_district`): 1-2 residential towns (200 / 30 / 10) per grown town on a site
  feature (upper / shore / across / lead / valley / clearing), named per language (reserved real names sometimes),
  linked by ot_link, arms shortened (0.75), no lane ahead, the gap waived along the link; saved `dk` / `dp`; DISTRICT
  lines; dev "Found a district". Mid-edge joins: not supported (crash rule), many pairs instead.
- DONE phase 2, **Works by a factory** + **robust link** (`ot_link`): site 2/3 of the way to an industry within 3 km,
  named by its kind; links from many pairs and detours, planned in turn until both ends join.
- DONE phase 3, **coastal huggers**: 1-2 per map by coastline rings; strong shore form, depth 150-230 m; COASTAL lines;
  frame `cs`.
- DONE phase 4, **bridges**: more narrow-water origins, dry far streets, candidates tested against obstacles beyond the
  snapshot, 3 tries with the refused crossing skipped, next bridge type after a CNP; research: only
  `townConnectionMaxBridgeLength` is readable.
- DONE phase 5, **squeezed towns**: `squeeze` (slope / water / forest, two at least) leans the form draw to clustered.
- DONE phase 6, **stop names**: street sections and variants (compass, Upper / Lower, Old / New, far end, landmark per
  language), saved bases `sb`, 28-character cap, town words, clumsy pairs, more parts.
- DONE coordinator additions: Act on Off skips preRunFn (PRERUN line; tooltip in 13 languages; PLAN 8 fixed); density
  (DENSIFY 1.2, free-lot brake, sparse upward dose); lanes ahead shorter and curved; ALLTOWN street / empty / dead-end /
  pb fields, SIMGROW year frames / gapHeld; bridge research.
- Tests: main 517 / dev 120 green.
- Next: TESTING.md "Round after the 2355 run".
- **Addendum after run `2026-10-14_0119_sqot`** (2026-10-14; details PLAN.md 6.3 "Round after the 2355 run" addendum;
  in game: TESTING.md "Addendum after the 0119 run"):
  - DONE **created-town race**: one creation in flight map-wide; the created town claimed only by its name near the
    site (`ot_works.identify`), else `created ... why=unidentified` and never claimed; claims saved with the site.
  - DONE **load check**: wrong saved claims dropped (EV_WORKS kind=drop), lost creates adopted by their parent or
    logged as orphans (OFFSHOOT lines); the 0119 save is repaired on its next load.
  - DONE **forest**: no clearing districts; every Works / district site rejected above 0.2 forest cover within 450 m
    (`why=forest`), forest-edge sites preferred; offshoot towns hug the forest from their first build; `forest=` on
    create. A Works / district under 120 buildings gets no mod streets (Penkridge Sands' streets were the parent's).
  - DONE **"Satellite towns" setting** (On / Residential only / Industrial only / Off, 13 languages) and **varied
    names** (least-used form per kind, era forms, hill sites, no water word twice).
  - Tests: main 523 / dev 120 green.

## 39. Round after the same-seed comparison: no capacity boost, density, straight empty lanes, the angle split, measurement (2026-10-14; details PLAN.md 6.3 "Round after the same-seed comparison"; in game: TESTING.md "Angle split run", "Fresh run after the comparison round")
- Evidence: BASELINE_VANILLA.md "Same-seed comparison 2026-10-14" (session `2026-10-14_0119_sqot`, seed `U8Qxgisp4I`):
  2.9 vs 6.4 persons per building, 7.6 vs 3.8 m of street per person, 58 vs 52 % free lots, +15 % people from the dose
  fill's capacity boost, long straight empty lanes. Findings recorded: towns.md (at 35° the generator's starting towns
  have 29 % more, smaller buildings for the same people; DevelopAt's upgradeBuildings changed nothing).
- DONE phase 1, **no capacity boost**: FILL_EXTRA 0 (dose), ot_metro FILL_EXTRA / POLY_EXTRA 0; every fill restores the
  initial capacities exactly; raised old saves keep theirs (never lowered) and dose again; INIT / FILL restore
  `capsBoost=0`. The other capacity writers checked (dev SIMGROW, Starting town size, testing GROW, Works / districts).
- DONE phase 2, **density**: the demand brake on free lots (FREE_AIM 0.5) x persons per building (PB_AIM 4.5), `why=free`
  instead of room builds above 55 % free; UPWARD without the surge hold, sparse from 250 buildings under 4.5; **level
  weights** (`LEVELS`: new maps, 150+ buildings under 4.5 persons per building, weights toward levels 3-4 by how sparse,
  cleared at 5.5, never a player's own weights, saved `lw`).
- DONE phase 3, **straight empty lanes**: they were satellite links. Links are winding country lanes (no lots, no
  straight run over 150 m, the gentlest grade of 4 variants), 0.65-1.2 km out, at most 900 m long, their core dosed; lanes
  ahead and Works / district links planned curved; the straight-run guard drops new straight town streets more than
  250 m ahead of the houses (PLAN `straight=`).
- DONE phase 4, **the angle split**: Game default already leaves the angle at 0 and the driver never uses it; run steps
  in TESTING.md "Angle split run".
- DONE phase 5, **measurement**: ALLTOWN `ind=` (industries in town / enclosed) and `lvl=` (level shares), the tour
  waits for town creations, `compare/build_compare.py` (+ `compare/template.html`) rebuilds the comparison for any two
  loads.
- Tests: main 529 / dev 120 green (loosened thresholds listed in PLAN.md 6.3).
- Next: TESTING.md "Angle split run" and "Fresh run after the comparison round".

## 40. Round after the 0302 run: branch out young, build up grown, offshoots back, the three-run page (2026-10-14; details PLAN.md 6.3 "Round after the 0302 run"; in game: TESTING.md "Retune run after the 0302 run")
- Evidence: run `2026-10-14_0302_sqot-sqrl` load 2 on the comparison seed `U8Qxgisp4I` (BASELINE_VANILLA.md
  "Density-round run"): buildings 1701 -> 7939 (0119 mod 15665, vanilla 6547), pb 6.33 (2.94 / 6.37), the mod 11 % of
  the edges (24 %), 235 of 279 CHECKs `why=free`, spread 1.13 (1.19 / 1.20), 3 satellites / 0 districts / 0 Works
  (8 / 9 / 3), LEVELS on all 16 towns early with no level 3-4 building anywhere. The user: less variation, more buildings
  in the centre; likes towns that branch out early and build up later, not before; no satellite villages seen.
  Finding: towns.md (levels 3-4 only from 1950 / 1990; the game's 35° towns keep ~60 % of lots free).
- DONE **page**: `compare/2026-10-14_U8Qxgisp4I/` holds three runs (Mod 0119, Vanilla 0119, Mod 0302; shots
  `mod-0302/`); pick A / B (side by side, slider, ratio column) or all runs in a row; `build_compare.py --add / --rebuild
  / --relabel`, data.json `version: 2` with a runs list. Checked in headless Chrome (desktop, 390 px phone frame).
- DONE **maturity** (`ot_assess`): MAT_LO 1800 / MAT_HI 3600 persons; demK phases in, the `why=free` hold too (young:
  never); CHECK `mat=`. Persons, not buildings (the brake changes the building count) and not age (one age per map).
- DONE **pbK per building** (was per built lot: x0.6 even at vanilla density) and **FREE_AIM 0.55**, band 0.5-0.7.
- DONE **LEVELS for grown towns** (`ot_upward` LV_MAT 0.5, k x maturity; `skip=young`, LEVELS `mat=`); town-wide only.
- DONE **offshoots**: their gates read max(buildings, persons / 4); an offshoot turn (snapshot + satellite / Works /
  district decisions + a waiting link, at most every 240 s per town) for towns that need no streets; OFFSHOOT
  `event=turn`, BUILT `trigger=offshoot`.
- Offline: test_demand "maturity" (young phase 48 % mod share as without the brake, 30 % with the 0302 brake; grown
  25 % against 32 %, pb 4.38 against 4.31; the grown phase directional only), "offshoot turns" (two tests).
- Tests: main 532 / dev 120 green (changed tests listed in PLAN.md 6.3).
- Next: TESTING.md "Retune run after the 0302 run" (same seed, one mod run), then `build_compare.py --add`.

## 41. Dev Simulate speed-up and Build out (2026-10-14; dev mod only; details PLAN.md 6.3 "Simulate natural growth" "Speed-up and Build out"; in game: TESTING.md "Simulate speed-up and Build out")
- Evidence: run `2026-10-14_0302_sqot-sqrl`, Quick 40 years 175 s: 30 s of pace, fills 94 s (the long ones queued behind
  the main driver's own build right after the round), rounds 29 s.
- DONE pace 0 (Quick), main driver held through the fill, early fills during the round, `ROUND_INFLIGHT` 24 with the
  plan-extent neighbour rule, Fill every 1 / 2 / 4 / 8. Expected Quick ~95-110 s, same size targets.
- DONE **Build out: 100 years** (10 chunks, every town, tour; upward / level gaps lowered for the run; `SIMGROW chunk`).
  Expected ~3.5-4 min (forced houses ~100 per s).
- DONE optional "Move the game date with the simulated years" (`makeGameSetDateCmd`, forward only; default off): without
  it a 1900 map never gets level 3-4 buildings in the sim.
- Main mod unchanged. Tests: dev 120 -> 131 green.

## 42. Generated names: towns, rivers, lakes, districts and Works named from the landscape (2026-10-14; details PLAN.md 6.3 "Generated names"; in game: TESTING.md "Generated names test")
- User: "skip the european name set and use our own more interesting and very procedural and reactive to environment
  names", "the more specific to the terrain the better".
- DONE: "Town and stop names" value 3 Generated names (appended; default stays Landscape names), tooltip in 13
  languages, description Features / Settings / Changelog.
- DONE: `ot_placename.lua` + `ot_placename_lang.lua`: fine site tags (49 terrain tags incl. confluence, mouth, bend,
  spring, tarn, mere, pool, sandy / rocky / cliff coast, bay, spit, headland, island, hilltop, slope, ridge, pass, foot,
  mountain, gorge, combe, vale, fen, moor, heath, clearing, edge, 21 tree species) with specificity weights; a cheap
  extra read per town (water arms, ring heights, altitude); inventories for en, usa, de, fr, it, es, pt, nl, sv, nb,
  ja / ja_r; regional dialects; rare forms for character towns; affixes; river and lake names shared by their towns
  and saved (`rv`) for the stop names; phonotactic rules, a blocklist, never a real list name, unique per map,
  deterministic per seed; satellites; related district names and industrial Works names.
- DONE: driver names phase in generated mode (no classify; `namesAssignGen`), fallback to landscape names for lists
  without a generator (ru, pl, zh, ko, asia, oceania; `fallback=noGenerator`).
- Tests: test_placename.lua 15, test_names.lua +3; main 557 / 0.
- Risks: the read's thresholds are untested on real terrain; the river-system linking only knows each town's own river
  axis (a winding river may split into two names); long affixed names (up to 30 characters) on the map labels; some
  combinations read odd in a language (native-speaker corrections welcome); the it / es / pt / fr inventories are
  smaller than en / de / usa.
- Next: TESTING.md "Generated names test".

## 43. Deep forest towns: winding, wooded, secluded towns in dense forest (2026-10-14; details PLAN.md 6.3 "Deep forest towns"; in game: TESTING.md "Deep forest towns")
- Evidence: the user ("push some towns that are in particularly dense forested areas to lock more often around trees, to
  really try to make them winding, wooded, secluded towns"); Verwood / Dewsbury liked (fingers between forest patches,
  woods kept).
- DONE **who**: forest mode `deep` (ot_forest deepPick): growth-ring (150-900 m) forest share >= 0.45, seeded 0.75 x
  style (organic growers + Nordic) x tier (never tier 4) x era x character, never a metropolis / offshoot, at most 3 per
  map; saved on the frame (`fd`), so a deep town never flips and towns framed before stay as they were. FOREST
  `mode=deep why=`.
- DONE **winding**: ot_forest.deepStyle in ot_style.resolve: curve / jitter / contour up, smaller blocks, no outer zone,
  a shorter spoke wobble, spokes steering at LINE_RADIUS, bowed secondary radials and lanes (ot_grow_organic.wiggle,
  radius-checked); offline max straight 70-72 m (hug 137-171 m), geoBad none.
- DONE **locks**: every new street with forest within lot depth (`side`) or within ~90 m (`near`), dead ends into the
  trees (`tip`); offline 100 % of the forest-adjacent edges (hug 55-67 %). The game's own streets can't be locked.
- DONE **lanes** 2 of 3 eligible crossings (8 per town); single-sided lanes not built (no safe variant).
- DONE **clearing**: a quarter of the budget, wooded lots x 1.5, groves (forest patches <= 4 ha inside the town's frame)
  never cleared by the mod (`groveHeld=`); a creep minimum of 120 m per increment so a town in the woods still grows.
- DONE no level weights, no districts / Works (`why=deep`).
- DONE logs STYLE `deep=`, PLAN `deepLocks= bends= maxStraight= groveHeld=`, ALLTOWN `forest=..:deep`; dev "Force deep
  forest" (DEEPDEV).
- Tests: main 539 / dev 132 green (test_deep new; dev test_runner +1).
- Next: TESTING.md "Deep forest towns" (with the next same-seed run, `U8Qxgisp4I`).

## 44. Round after the 0502 and 0613 runs: LEVELS vs the engine's weights, a mature hold, sim speed, empty satellites and bridge ends, name tags, links (2026-10-14; details PLAN.md 6.3 "Round after the 0502 run"; in game: TESTING.md "Seed a run")
- Evidence: run `2026-10-14_0502_sqot` (seed `Z2tNDhy0Ht`, BASELINE_VANILLA.md "Retune run 2026-10-14 0502") and run
  `2026-10-14_0613_sqot` (seed `a`, Generated names, "Seed a run 2026-10-14 0613"): young towns branch out (worked), grown
  towns don't build up (pb 3.08 / 2.92, LEVELS `skip=player` everywhere, `why=free` never), Quick 231 s / 182 s with HEAD
  rounds after the stop, empty satellite skeletons, a bridge ending at an empty cross, links 1 of 7, misfiring name tags,
  no deep town, the tour's first shot 925 m off. From now on the user plays seed text **`a`**.
- DONE **LEVELS baseline** (phase 1): at the mod's first sight of a new map (game clock under FRESH_GAME_TIME, no baseline
  saved) every town's custom weights are saved as the engine's baseline (EV_LEVELBASE, ot_saved `lb` / `lbs`); weights
  equal to the baseline are the engine's (`owner=engine`: LEVELS runs), equal to ours `ours`, anything else the
  player's; no baseline (an old save) keeps the old rule. A clear goes back to the baseline. Probe `LEVELS read` (every
  town at load, changed towns after every SIMGROW round). LEVELS lines carry `owner=`.
- DONE **mature hold** (phase 2, ot_assess MATURE_*): demK capped at 1 - mat x capK x 0.82 (0.18 at maturity 1), phased in
  over 50-55 % free lots; from maturity 0.5 no demand build while free lots exceed 0.60 + (1 - mat) x 0.5 (`why=mature`,
  the demand stays in the bank); young towns untouched. MATURE lines (`event=hold|cap|off`). Offline (test_demand
  "maturity", 3 seeds): grown-phase mod share 41 % -> 34 %, end pb 4.24 -> 4.32 (the model's pb barely moves: its lots
  hold a fixed capacity; directional only).
- DONE **sim speed** (phase 3, dev): `H.simNoFills` during build rounds (no dose / upward fill; core / lane-end / far-bank
  doses still go), SG.ROUND_BUILDS 6 -> 3, Quick / Build out refused until `HEAD done` (greyed `sqotd-wait` buttons,
  runner REFUSED `headStart`), SIMGROW year `added= perS=`. FILL_RATIO / final-fill option not done (no offline model of
  the fill's speed).
- DONE **satellites** (phase 4): CORE_SMALL (3 core edges), the seed dose never held by the surge rule (5 of 10 seeds
  had none in 0502), a core redose REDOSE_S 45 s after the build (up to 2, `FILL why=satCore`: the seed's own dose came
  before the lots existed, near=0->0 on all five), `SATELLITE retire` after 10 empty checks (no more streets, the gap
  meadow released).
- DONE **bridges** (phase 5, ot_bridge): CROSS_LATER (no cross street at the far end: the far street ends at C), a far-bank
  dose at the build and a redose (`why=bridgeEnd`), APPROACH_MAX 260 m, approaches over 120 m bend once (a waypoint, the
  same template). Budleigh Salterton's 384 m straight approach would now be refused (or bent under 260 m).
- DONE **name reserve** (phase 6): `self.nameReserve = NM.reserve(...)` after the landscape assignment (this session
  only); Generated mode keeps `PN.related`.
- DONE **name tags** (items 8 / 13, ot_placename): `edge` only with real contrast (ot_forest.isEdge: open town, a ring
  sector >= 0.45 wooded, another <= 0.12); species by lift over the map's mix (`speciesMap`, SPECIES_LIFT 1.15); hill /
  vale need the disc's own height range (12 m); `island` only with a closed shore (else headland); `spit` with the tip
  within 800 m and water at the town; slope near the water level counts 0.3 ("Upper"); no "tarn" lake generic unless a
  town of the lake has the `tarn` tag; a river read by 16 rays to 700 m (`read= riv:`), 3 crossings make a river town.
- DONE **links** (item 10, ot_link): lead-out routes (leave along the dead end's own street, swing to either side, clear
  of the own street), 5 tries 60 s apart with a new seed each (was 3 x 300 s: never retried in a Quick run). The
  "town's nearest edge" start is not done (joining mid-street isn't supported: the crash rule).
- CHECKED **Works caps** (item 11): both Works were created with `caps=10/10/200`, the generated path changes only the
  name. CHECK now logs `uses=` (person capacity per land use) and `initials=` to see whether the industrial 200 is built.
- DONE **deep forest** (item 12): recalibrated, not rank-based (each town is picked before its first build, when the
  other towns' grids aren't read): the ring counted at DEEP_COVER 0.25 (~18 trees / ha), DEEP_SHARE 0.40, and woods
  around the town (5 of 8 sectors >= 0.25), so a forest-edge town stays a hug town.
- DONE **tour aim** (item 14, dev): a fallback shot with the camera more than 60 m off is aimed again first (`SHOT
  reaim`, at most 2).
- DONE **game-script gate test** (item 9; the fix itself by the coordinator): landscape / generated queue new Road Stops,
  game / Act on Off / map editor don't. Generated-name stop names use the saved river names (test_names "stop names
  stay on with Generated names ...").
- Tests: main 557 -> 569, dev 132 -> 133 (test_round0502.lua new; changed: test_demand level / maturity, test_satellite
  core size, test_ships bridge lines, test_deep half-wooded, test_district doubling back, dev test_simgrow round cap).
- Next: TESTING.md "Seed a run" (seed `a`), then one true-vanilla run on `a` for the comparison page.

## 45. Names from the map's shape: fewer repeated words, big geographic cues (2026-10-14; done offline 2026-10-14; details PLAN.md 6.3 "Names from the map's shape"; in game: TESTING.md "Names from the map's shape")
Source: run `2026-10-14_0710_sqot` (seed `a`, USA names, Landscape names; page `compare/2026-10-14_a-usa`). User:
> "we have too many repeat words in city names. lake, woods, etc. it sounds unrealistic and silly when its like that.
> it would be cool if we could really take into account the shape of the map. e.g. middle fork, directionality, big
> geographical cues would be super neat."

Evidence (NAME lines): 9 of 16 starting towns carry Lake / Forest: Forest Lake, Canyon Lake, Lake Forest, Kendale Lakes,
Lake in the Hills, Lauderdale Lakes, Wake Forest, Park Forest, Forest Hills. `lake:1.00` scored on 6 towns,
`forest` on 15. A tag that every town reads is no cue. `Milford_city_` (the list's "Milford (city)") kept a list
disambiguator.

Rules: CLAUDE.md (loop caps on every trace or walk, test only this mod and the dev mod if touched, 13 languages for
new user-visible strings, no commits), don't impact saves (names are given once at first sight; never rename a named
town on load).

1. **Word budget, map-wide.**
   - Each generic landscape word (Lake/Lakes, Forest, Woods, Park, Grove, Hill(s), Heights, Bay, Falls, Creek, River,
     Valley, Springs, and each language's equivalents and affixes) appears in at most about 1 per 8 towns. Never twice
     within neighbours (about 5 km), counting towns, districts, Works and satellites. Stops count separately: vary
     their suffixes.
   - Score tags by map rarity, as the species read does: a feature most towns share weighs little. The rare,
     distinctive cue wins.
   - Applies to Landscape (list) picks, Generated names and district names.
   - Log `NAMES words used=lake:2,forest:2,... held=` once per map.
2. **Map survey, once per map, sliced and capped.** It reads the big shapes and keeps them for every naming step:
   - **Rivers as a network.** Forks and confluences ("Forks", "Middle Fork", "Three Rivers", "Junction", "Twin
     Rivers"), mouths at the sea or a lake ("-mouth", "Port X", "X Mouth"), sharp bends ("Bend"), steep drops ("Falls",
     "Rapids"). Upper or Lower follows the flow, from elevation along the river. One river name is shared by the towns
     along it ("X Falls", "Upper X").
   - **Direction on the map and to big features.** North / South / East / West / Central against the map extent and
     against a big feature or a twin ("North Bend", "East X", "West Lake X").
   - **Big features named once and reused as qualifiers:** the map's largest lake, the highest peak or range ("Mount
     X", "X Gap", "Summit", "Divide", "Pass"), the main valley, bays and capes, narrows between waters, isthmus.
   - Log `NAMES survey rivers= forks= mouths= lakes= peaks= ranges= ms=` and per town `cue=`.
3. **Per language.** Each generator language gets its own cue words. Examples:
   - US: Fork, Bend, Gap, Divide, Summit, Forks, Junction;
   - UK: -mouth, Upper/Lower, Nether, Great/Little, -bridge, -ford, Kirk;
   - DE: Ober-/Unter-/Nieder-, -mündung, -eck, -furt;
   - FR: -sur-X, Haut-/Bas-, -les-;
   - and so on for the others the generator has.

   "The more specific to the terrain the better." Landscape mode can't invent words, so it prefers list names that
   carry a matching cue (a "North ..." name in the north, a "... Fork(s)" name at a confluence) and the word budget.
   Generated mode composes the cues.
4. **Clean list names:** strip disambiguators such as "(city)", "(town)" and "(CDP)", in the town, its industries
   and its stops.
5. **The name lab** (`plans/square_organic_towns/names/`): port the new rules (`check_port.js` stays green), so the
   user can try them.
6. **Tests:**
   - 16 towns that all read lake: at most 2 lake words;
   - a fork or confluence fixture gets a fork name;
   - direction by map position;
   - a river shared along its towns;
   - "(city)" stripped;
   - deterministic per seed;
   - survey caps hit means logged and skipped.

Results (2026-10-14, offline):
- DONE **word budget** (`ot_namewords`, new): generic words per list language (14 lexicons incl. the compass and Upper /
  Lower), at most ceil(towns / 8) per word and never within 5 km (SOFT words: -ford, -bridge, -bach, -berg ... twice /
  half); Landscape names also any other repeated whole word ("North / South Plainfield"); districts, Works and
  satellites pay only for words their parent's name lacks; stops vary their last word instead (ot_stopname.pick). Tag
  rarity in both modes. `NAMES words used= held= cap= near= over= rare=`.
- DONE **map survey** (`ot_mapshape`, new; names phase `shape`): <= 128 x 128 cells, sliced (2 ms), capped per phase and
  at 45 s; rivers as a network (forks, mouths, bends, falls, upper / lower course; towns on one river share its name),
  sea / lakes, the big lake, peaks, the range, the main valley, bays, capes, narrows, isthmus; per-town cue tags and
  `cue=` on NAME lines; `NAMES survey rivers= forks= mouths= ... capped= ms=`.
- DONE **per language**: Landscape cue words for 14 classifiers (North / Upper / Forks / Falls / Bend / Gap / Summit /
  Mount / -mouth / Nord- / Ober- / Unter- / Haut / Bas / -fors / 北 ...; fork / falls / mouth strong, the compass a
  preference); Generated cue tags, `%t %m %M %b %B %D %E`, whole-name affixes and new forms in all 11 generator languages
  (usa Forks / Three Rivers / Middle Fork / Falls / Gap / Summit / Divide / Mount; en Myton-style stems, -under-, Fell;
  de Norder- / Wester- / -münden; fr Haut- / Bas- / Condé-sur-; it Bocca di; es Juntas; pt Foz do / Entre-os-Rios; nl
  Noord- / -mond / Boven-; sv Norra / -fors / -mot; nb Nordre / -foss / -os; ja 北 / 落合 / 川合); features named once (usa,
  en: the mountain and the bay).
- DONE **clean list names** (`NW.clean`): "Milford city " -> "Milford" (town, its industries, the reserve; stop street
  names trimmed).
- DONE **name lab**: gen.js / export_names.py / port_check.js / lab.js (cue presets, cue golden towns, "Word budget"
  checkbox); check_port 948 / 948.
- Tests: test_nameshape.lua (new, 16: all six listed + the 0710 replay, cost, the driver phase); test_names two order
  tests without the budget. Replay of 0710's 16 towns: lake 2, forest 0 (was 9 of 16 Lake / Forest).
- Not done: feature names (mountain, bay) only in usa / en (other languages use the cue forms without a named feature);
  the survey isn't saved (later district / Works names read the cues of no survey: budget only).
- Next: TESTING.md "Names from the map's shape".

## 46. Bridge stops and the one-line bridge fix (2026-10-14; done offline 2026-10-14; details PLAN.md 6.3 "Bridge stops"; in game: TESTING.md "Bridge stops")
Source: run `2026-10-14_0814_sqot` (9x `ERROR stage=snapshot ... ot_satellite.lua:240: attempt to index local 'pts' (a
nil value)`) and the user's idea: "one opportunity is if a bus stop is on a bridge, we could use that as a big cue."

- DONE **one-line bridge plans** (the 0814 error): since §44 (CROSS_LATER) `BR.lines(c)` has one line when the bridge
  has no far cross street; the driver's candidate loop (`BRIDGE_OBST_SKIP`) passed the missing `ln[2]` to
  `SAT.clearOfObstacles`. Now the driver skips it and `clearOfObstacles` is clear for nil / under 2 points. The only
  other `BR.lines` caller is test_ships (line 1 only); `BR.farPoints` already checks its nodes. Tests: test_ships
  "bridgeDecide (run 0814)" (the driver's loop with a one-line plan: planned; a street across it: `why=obstacle`; fails
  with the 0814 error without the fix), test_satellite (nil / empty / one-point polylines).
- DONE **bridge stops** (`ot_stopname` BRIDGE / bridgeCue / bridgeNames, `ot_engine.stopBridge`, driver stopSite /
  stopName): a new Road Stop whose own street edge (the BASE_EDGE whose `objects` hold the stop) is a bridge
  (`type == BaseEdgeType.BRIDGE`), or within 6 m of a bridge edge when its edge can't be found, takes the bridge theme
  before every other (industry and section variants included): `<River> Bridge` (the generated river name within
  2.5 km), `<Town> Bridge`, Old / New Bridge (Old first before 1900), Bridge Street / Road / Lane; a stop off the bridge
  within 60 m of a bridge end: Bridge End / Bridgefoot / ... . All 14 stop-name classifiers (de Lahnbrücke / Alte Brücke
  / An der Brücke, nl -brug, sv -bron, nb -brua, fr Pont d'... / Pont Neuf / Tête de Pont, it / es / pt Ponte / Puente,
  ja 橋 / 大橋 / 橋詰, ru Мост через ... / Старый мост / У моста ...). Unique map-wide; the variety window holds only
  bridge names while one is left; none left: the stop's other themes. STOPNAME `bridge=1|end|0 bridgeRead=edge|near|end|
  noEdge|fail river=`. Tests (test_stopname, 5): the cue, every language, 20 bridge stops distinct, non-bridge stops
  unchanged, the driver with a fake engine (bridge=1, Bridge End, near, a throwing read falls back to the normal name).
- Not verified in game: that a street stop's station entity is the entity in its edge's `objects` list (else the 6 m
  fallback decides), and the edge `type` read. Next: TESTING.md "Bridge stops".

## 47. Satellite and Works name variety (2026-10-14; done offline 2026-10-14; details PLAN.md 6.3 "Satellite and Works name variety"; in game: TESTING.md "Climate-led names", step "Created towns")
User: "industrial satellites seem like they always say 'works' or very often. make sure our satellites have lots of
variety too." Evidence (compare/*/data.json extraTowns): "Works" on 7 of 11 Works towns, always "<Parent> <suffix>";
districts Sands x4, Beach x3, -on-Sea x3, Point / Shores / Bay / Heights x2 (any water within 170 m made a "shore" site,
a river bank too; the first form of a kind won every tie).

- DONE `ot_offname` (new, pure): Works by the industry's own type (`indType` over the file: 19 families, steel -> iron,
  glass works -> glass ...) and the site / survey cues, in four patterns per list language: parent ("Haslemere
  Glassworks", "Zeche Heywood"), company (founder towns "Crossleyville", "Port Garside", "Kolonie Ewald",
  "Gustavsberg", "Colonia Ibarra", "New X"), cue (root + site word: "Ironbridge" by a river, "Furnace Vale", "Saltport"),
  generic (Works / Depot / the era's estates, low weight). Shares parent 0.5 / company 0.25 / cue 0.25 per seeded draw.
- DONE districts: the site kind's forms, Upper / Lower by height, the compass from the parent ("North X", "X-Nord",
  "Norra X", 北X), Little / New, generics per language (-Green / -Common / -Fields; -Feld / -Heide / -Anger ...); beach
  words only on a sandy sea shore (survey or a local water read: `readWater`, 16 rays), lake words by a lake, never by a
  river or inland. The session-only real-name reserve is gone (§49).
- DONE variety: every form has a suffix key ("works", "*ville", "port+", "north+"); lowest map-wide count first (each
  suffix once per map until the map runs out), never a key a sibling of the same parent carries while another is left,
  then fit + seeded jitter. Counted from the map's names (stateless after a reload). All through the word budget.
- DONE logs: WORKS / DISTRICT create lines `pattern= suffix= fam=`; `NAMES offshoot used= n= new= pattern= suffix=` after
  each creation (the suffixes the mod's offshoots carry map-wide).
- DONE 14 classifiers (en, usa, de, nl, fr, it, es, pt, sv, nb, ja, ja_r, ru, ru_r). Old saves: only new offshoots get
  names, nothing renamed; `orphanOf` also knows the new parent forms.
- Not ported to the name lab: the lab has no offshoot names (its Port check note says so).
- Tests: test_offname.lua (10): 10 Works with mixed industries (no suffix > 2, Works <= 1, not all parent), 10 inland
  districts without water words, a sandy sea shore once per map, determinism, every language, the Asian list, the water
  read. test_works / test_district / test_round0502 / test_demand updated to the new names.

## 48. Asian maps and other untagged name lists (2026-10-14; brief; run `2026-10-14_0814_sqot` load 3, HISTORY.md)
User: "i ran seed A on tropical map for asian. i dont think landscape names worked. was it activated?" It was on, but
it renamed nothing: `NAMES on=true why=noTags list=asia pool=0`. The base Asian list holds ~100 world megacities, with no
landscape words (docs/findings/towns.md), and Generated names fall back to Landscape for asia. Open:
1. DONE (2026-10-14, option A; user: "a. do your recommendation"): **Names for an Asian map.** The user picks one:
   - keep the game's names and log `on=false why=untaggedList`;
   - draw from the china / japan / korea lists by map region, if they carry readable words;
   - a pan-Asian generator.
2. DONE (2026-10-14, §47): **Offshoots on untagged lists:** no English generics on Asian names ("High Wuhan", "Wenzhou Works"). Use the list's
   language, or a neutral pattern.
3. DONE (2026-10-14, offline): **Style spread:** `asia` maps to EAST_ASIA, and 14 of 16 towns came out JP_DENSE. Spread the styles for a pan-Asian
   list, and give the tropical climate its own bias.
4. DONE (2026-10-14, offline): **Character quota:** count only the map's own towns, never created satellites or Works (`towns=17 count=3` after a
   satellite).
5. DONE (2026-10-14): **The map survey** should run even when no names are given, so other steps can use it later.

Results (2026-10-14, offline): items 1 and 5: a list without a generator language keeps the game's names and logs
`NAMES on=false why=untaggedList list=asia` (china, korea, poland: untaggedList; russia and the ru folders:
`why=noGenerator`), the same in Generated mode; the map survey still runs (`NAMES survey ...` first) and stays in memory
for the offshoot names (`Driver.mapShape`). Item 2: their Works and districts take an unused name of the list itself
(`Driver:offshootListName`, `pattern=list`), never English words.
Items 3 and 4 (2026-10-14, offline; PLAN.md 6.3 "Style spread on the Asian list, tropical bias, character quota"; in game:
TESTING.md "Climate-led names" step 9): the asia list is region ASIA with its own mixed bias (EU_ORGANIC 2, JP_DENSE 1.6,
SUPERBLOCK 1.6, MED_HILL 1.4, grids and the extension ~1); china / korea stay EAST_ASIA, japan JP. On 16 varied synthetic
sites: asia tropical 1900 EU_ORGANIC 6 / JP_DENSE 4 / EU_EXTENSION 4 / NA_GRID 1 / MED_HILL 1, no style over 42 % on 160
towns per case (tropical, temperate, dry; 1900 and 1960); the japan list stays JP_DENSE-led (124 of 160 on a tropical
map). Tropical has a style bias now (suburbs 1.8, extension 1.5, organic 1.2; JP dense / MED hill 0.6, Nordic 0.3) and a
form bias (sprawling 1.5, linear 1.3, radiating 1.25, clustered 0.6, shore chance x1.3 under its cap; blocks x1.15 as
before). Dry and subarctic checked: kept, plus dry Nordic 0.3, subarctic MED hill 0.5 / ensanche 0.7. Character quota:
Works and district towns are left out of the ranking (`CHARACTER towns=<own> created= fixed= count=`), a saved pick stays
(frame `ch`), a framed town without it never becomes one. Tests: test_site (4), test_map (1).

## 49. Plausible, climate-led names: no real list names, climate and survey fit (2026-10-14; done offline 2026-10-14; details PLAN.md 6.3 "Plausible, climate-led names"; in game: TESTING.md "Climate-led names")
Source: run `2026-10-14_0814_sqot` loads 4 (usa, tropical island map, survey `lakes=0 sea=true bays=37 capes=33`) and 6
(europe, same map). Load 4: two towns tagged `lake:1.00` became "Lake in the Hills" and "Canyon Lake"; "Cottonwood
Heights", "West Hollywood", "Marlborough" (`match=plain`). Load 6: Darley Dale, Penkridge, Ellesmere, Haslemere, Chipping
Campden, Swanscombe and Greenhithe ... real English towns on tropical islands. User: "make sure names don't sound silly -
like lake in the hills on a tropical map where its all islands" and "our names should all be heavily influenced from the
region (tropical, subarctic, etc.) otherwise the naming falls apart. in landscape name mode i'd prefer not to use real
existing city names, and instead all generated names from region and geography cues and similar".

- DONE **Landscape = the generator**: "Landscape names" (the default) and "Generated names" both run ot_placename with
  the climate; no list-name matching for towns, districts, Works or satellites. The driver's list matcher
  (`namesAssign`, the classify phase, the district name reserve) is retired; ot_names keeps its pool / classifier for
  the stop names and the tests. The setting keeps its three values (saved indices unchanged: 1 landscape, 2 game,
  3 generated); "Generated names" is now an alias of Landscape names (kept in the list so older saves that chose it keep
  their value; its tooltip says so). Name and tooltip text in 13 languages.
- DONE **climate first-class** (`ot_climate`, new): `key` (tropical / dry / subarctic / temperate from the climate path),
  tag vetoes per climate (tropical: no oak / birch / pine / heath / moor ...; dry: no marsh / fen / meadow; subarctic: no
  palm / coral / lagoon), the climate's site tags (tropic + palm, reef, lagoon, mangrove; arid + dune, mesa, wadi;
  boreal + snow, birch, pine, moor), and a word check of finished names per language (`wordMisfit`). In ot_placename:
  new tags, climate words in every generator language (en / usa: Palm, Coral, Mangrove, Banyan, _Key, _Cay, _Reef,
  _Lagoon; Mesa, Sage, Yucca, _Wash, _Butte, _Wells, _Arroyo; Snow, Frost, Spruce, Tamarack, -fell; de Palmen- /
  Korallen- / -riff / Dürr- / Schnee-; fr Anse- / Morne- / Neige; es Palmar / Cayo / Laguna / Manglar / Rambla / Arenal;
  pt Palmeiras / Recife / Lagoa / Mangue / Sertão; it Palma / Laguna; nl / sv / nb / ja likewise), the veto in the part
  ranking and the affixes, the word check on finished, river and lake names; Works / district names too (ot_offname).
- DONE **survey agreement** (`PN.agreeSurvey`, `ot_mapshape.waterNear`): no lake / mere / pool / tarn tag without a lake
  (not the sea) within 1.5 km; a sea inlet becomes coast / bay. Logged: `NAMES words ... climate= misfit=<word>:<reason>`
  (climate vetoes and survey corrections).
- DONE **lists without a generator**: oceania speaks the English generator (settler style; `PN.LIST_LANG`); asia /
  china / korea / poland keep the game's names (`why=untaggedList`), russia `why=noGenerator` (§48).
- DONE **name lab**: data.js carries ot_climate; gen.js ports the veto, the word check and `o.climate`; a Climate select;
  golden runs on a tropical and a dry map (check_port 2844 / 2844).
- Tests: test_climate.lua (7): climate keys, word fit, the survey agreement, the load 4 / 6 replays (usa, en: no lake,
  canyon or temperate tree words, tropical words on several towns), every generator language x every climate (12 towns,
  no misfit word), offshoots follow the climate, oceania / asia; test_names: Landscape names never a list name, the
  russia / asia lists keep the game's names with the survey run (both modes).
- DONE (2026-10-14, offline) **stop names' climate fit**: `SN.climateKey` = `CL.key` (subarctic); `treesFor` drops the
  species the climate rules out; every candidate passes `SN.fits` (`CL.wordMisfit` with the proper names blanked; with
  the survey's water read showing no lake within 1.5 km, `CL.lakeMisfit`: no Lake / Lakeside / Mere / See / Lac ...; a
  stats "lake" unknown to the survey -> `lakeFix=noLake|sea`); bridge names never checked, uniqueness unchanged. STOPNAME
  `climate= noLake= lakeFix= misfit=climate:n,lake:n`. Found on the way: `ot_climate`'s lower case folded UTF-8 lead bytes
  under a locale `%u` (Swedish / German umlaut words never matched): ASCII only now; "First Street" is no fir. Offline
  (test_stopname, 14 list languages x 40 stops x climate): 0 misfits; tropical 1294 / dry 1175 of 2240 stops had
  candidates dropped (quick run of 160 per language). Tests: test_stopname (7).
- Not done: a Russian or Polish generator (the lists keep the game's
  names); a whole-name plausibility pass beyond the part tags (the generator only composes parts its site carries, the
  CONTRA penalties and the climate vetoes; "in the Hills" style list names are gone with the list matcher).
- Next: TESTING.md "Climate-led names" (seed `a` on temperate, tropical, dry, subarctic).

## 50. Name and character fixes after the 1729 run (2026-10-14; done offline 2026-10-14; details PLAN.md 6.3 "Name fixes after the 1729 run" and "Style spread ... character quota"; in game: TESTING.md "Climate-led names" step 10)
Source: run `2026-10-14_1729_add-money-100m` load 3 (seed `a`, europe list, temperate, Landscape names = the
generator, the dev Simulate running the builds) and load 4 (the same map, usa list). User: "i see multiple sand
suffixes, which we want to avoid too many duplicates".

1. DONE **One path for every created town's name** (load 3: Mytsands, Norsands, Strathsands with `pattern=generated
   suffix=-`, Mytsands by its parent's lake; load 4: Stone Beach, Forge Landing with `pattern=- suffix=-`). The driver's
   Works / district naming bypassed ot_offname whenever the GEN_OFFSHOOT_P draw gave `PN.related` / `PN.works` a name.
   Now `Driver:offshootName` is the only path (both kinds, every mode): the generator's name is one candidate of
   ot_offname (`pattern=generated`, its suffix key "*sands") under the map-wide suffix count, the siblings, the word
   budget, the climate and the site's water read; `OFF.shoreOk` keeps beach words (Sands, Beach, Strand, -on-Sea, Plage,
   Lido, Playa, Praia, 浜 ...) to a sandy sea shore, Sea to the sea, lake words to a lake, for composed names too;
   `PN.related` takes lake / rocky / beach site weights from the read. WORKS / DISTRICT `pattern=` and `suffix=` are
   always the chosen form's. A long parent's stem skips modifiers ("Great Mytbridge" -> "Mytbridge Ings", "South Cedar
   Valley" -> "Cedar Hollow"; was "Great Holme", "South Draw").
2. DONE **Roots and affix patterns in the budget** (Myt x3, "-under-Dun" x2 + "-under-Edge", haven x2; load 4: Spruce x2,
   Valley x2, Fork / Forks, Port Big Sandy + Big Sandy Valley + Big Sandy Junction, a bare "Narrows"). Read from the
   finished name (a reload counts the same): each word's root from the inventory ("^myt"), the affix family ("%under")
   and a rare template ("%!%s-under-%m", once per map); singular and plural fold to one word. Every non-SOFT key, old
   generic words included, is refused among a town's 7 nearest towns (`NW.HOOD`) and within 5 km, besides the cap of
   one per 8 towns. A composed offshoot form doesn't pay for its parent's keys; a generated one pays for every root
   (no "Mytsands" beside Mytmere). Feature qualifiers: a river / lake / mountain / bay stem in at most two names, the
   second only as a qualifier, one whole-name form per feature (Port Big Sandy, then no Big Sandy Valley / Junction;
   Mount Spruce, then no South Spruce Valley). Bare one-word whole names (usa Narrows, Divide, Summit) take the town's
   name in front.
3. DONE **Dialects** ("Invercoed": Gaelic Inver- + Welsh coed; "Acbottom"). Per-language `compat` pairs; two grouped
   parts of one name come from one group or a listed pair: en saxon:norse, celtic:gaelic, celtic:welsh (en's celtic
   split into gaelic, welsh and shared celtic, with gaelic / welsh anchors); usa east:mid, mid:west; de nord:mitte,
   mitte:sued; fr nord / sud with centre; nl, sv, nb: none (it, es, pt, ja have no groups). Order: the Celtic prefix
   generics already come first (Inver-, Aber-, Pen-, Llan-) and take only a stem of their group or a river. Registers in
   en: `+f` stem fragments (Ac, Myt, Twy, Wel, Sal, Lin, Stan, Chip, Nor ... and the personal names) never take a `+w`
   generic that wants a whole word (-bottom, -edge, -side, -water, -grove, -hill, -head, -hall, -marsh, -heath, -moor,
   -sands, -ness, -naze, -port, -haven, -wood). The other generators were checked for the same class (test over seeds
   and the replay towns): no incompatible pair left.
4. DONE **Character quota** (`towns=16 created=0 fixed=0 count=2`, then 19 / 21 / 22 with `created=0`, the picks changed
   at 22). Cause: the dev Simulate's builds run on pool drivers (otd_runner `poolDriver`) that share `towns` with the
   main driver but not `saved`, `worksTowns` / `districtTowns` or the character cache: no created town, no frame, a
   fresh ranking in each pool driver (the repeated CHARACTER lines). §48 item 4 covered the main driver only. Now
   `Driver:root()` (ot_hooks.main when this driver shares its `towns`) holds the cache, the session picks (`charSticky`:
   a pick stays a pick before its frame is saved) and the one creation in flight (also map-wide under Simulate);
   `Driver:createdTowns` reads the saved `wk` / `dk`, both drivers' claimed sets and the parents' creation records; a
   town that appeared while a creation is in flight counts as created until identified. The dev mod is unchanged.
- Tests: test_namefix.lua (7): the load 3 / 4 replay (en, usa; no root, pattern or qualifier among neighbours), the root
  and pattern keys of the run's names, bare whole words, dialects in every grouped language, the driver's offshoot path
  with a fake engine (no beach word off a sandy sea shore, each suffix once, real pattern / suffix), printed samples,
  and the 1729 character sequence (16 own towns, created 3 / 5 / 6 on a pool driver, a pending creation, frames lost:
  the picks never change).
- Samples (offline, seed 1, the load 3 towns; districts: lake shore, sea shore, upper, valley, across, lead; Works:
  machine factory, steel mill by rail, fishing harbour):
  - en temperate: Lower Brynhaven, Mytbridge-under-Skid, Abercuckmere-on-Rydalwater, West Acmouth, Ashmere,
    Wheatbottom, Woodport, Ashminster St Brannoc, East Oakness, North Twyley, South Bradwood, Acworth,
    Mershaw-in-the-Vale, Osholt, Hartden, Abercoed-under-Edge; districts Abercuckmere Lakeside, Acworth Strand, North
    Twyley Hill, South Bradwood Dale, Mytbridge Ings, Ashminster Cross; Works East Oakness Tool Works, Mytbridge
    Steelworks, Acworth Harbour.
  - en tropical: ... West Swanmouth, Holtmere, Brockport, Woodminster St Brannoc, East Rosness, Swinworth ...;
    districts ... Swinworth-on-Sea, Woodminster Gate; Works East Rosness Locomotive Works, Mytbridge Steelworks, Port
    Swinworth.
  - usa temperate: Mount Signal, Middle Fork, Port Pine, West Turkey Bend, Lake Laurel, Prairie Canyon, Crystal Cove,
    North Antelope Woods, East Oak Point, Turkey Valley, South Cedar Valley, Hickoryfield, Mirrordale, Ellis Grove, Long
    Oaks, Three Rivers; districts Port Pine Lakeside, Hickoryfield Beach, Turkey Valley Heights, Cedar Hollow, Middle
    Fork Crossing, Antelope Corners; Works East Oak Point Car Shops, Furnaceton, Millport.
  - usa tropical: ... Port Rock, East Swan Point, South Palm Valley, Magnoliafield, Longwood ...; districts Port Rock
    Plains, Magnoliafield Beach, Palm Hollow ...; Works Hollisterburg, Furnaceton, Magnoliafield Fish Camp.
- Not done: the name lab (gen.js, check_port) has none of these rules yet; feature stems of a reloaded map's rivers
  count as roots for later offshoots (the survey and the water names aren't in the offshoot budget after a reload).
- Next: TESTING.md "Climate-led names" step 10.

## 51. Staggered satellites: offshoots paced map-wide, at staggered times (2026-10-14; done offline 2026-10-14; details PLAN.md 6.3 "Staggered satellites"; in game: TESTING.md "Staggered satellites")
User: "make sure satellites don't get built during the same period. e.g. we want satellites to happen naturally at
interesting staggered periods." Run `2026-10-14_1927_sqot` (seed a, europe, dev Quick 40 years, build rounds every 4
simulated years): 3 satellite seeds before year 1 (in or right after the head start), then bursts (year 11: 3 seeds, a
Works, a district), 12 seeds + 2 Works + 4 districts in all; every town decided on its own, no map-wide pacing.
1. **Per-town readiness.** A town's first, second and later offshoots unlock at seeded milestones: its size (buildings
   or persons / 4) at least its starting size (the frame's new `b0`) x 1.3-2.3, and at least a maturity size 260-480,
   both seeded per town; each later one x 1.35-1.9 further. None in the head start.
2. **Map-wide spacing.** At most one founding (seed, Works or district) per slot. A slot opens when the map's size
   (every town's persons / 4, the mod's own Works / district towns left out) grew by `need` since the last founding:
   520 on a 16-town map x (towns / 16)^0.5, x a seeded 0.6-1.7 per slot; when the calendar moves, 10 game years open
   one alone (growth / need + years / 10 >= 1). The first slot counts from the towns' starting sizes. In the dev
   Simulate (no calendar), at most one per build round (ot_hooks `simRound`), the mark set at the founding round's last
   check.
3. **Order with variety.** The ready towns are candidates (seen within 15 min); the one with the highest seeded key
   (u^(1/w), w = readiness x site quality: a town whose founding failed weighs less) founds, the rest wait. In a
   Simulate round the draw takes only the towns still to decide in it. A failed founding (no site, no name, not sent,
   refused, seed refused) gives the slot back, and that town sits it out.
4. **Grows.** A pod grows every 3-5 demand builds of its town (seeded per pod, seeded phase), once its town grew 8 %
   (25 at least) since the pod's last growth and the map 0.12 x need since the last growth of any pod.
5. **Saved, reload-safe.** `sp` = { m = the map's size at the last founding, y = its game year, n, y0, h = elapsed
   years } (EV_PACE), frame `b0`; both additive, old saves load without them (counted from the towns' initial
   capacities). The map's size is read whole at each decision, so a reload releases no backlog.
6. Lines: `SATPACE town= name= kind=seed|works|district k= ready= size= target= start= mapGrowth= need= years= cands=
   winner= outcome=found|wait|deferred why= n= simYear=` (wait lines debug, only when the town's reason changes),
   `SATPACE outcome=refund`, `SATPACE kind=grow ... podGrowth= mapGrowth= outcome= why=cadence|town|map|due`,
   `SATPACE summary founded= decades=0-9:a,10-19:b,... years= minGap= grows=` (debug after foundings, and at the dev
   Simulate's stop).
7. Tests (test_satpace.lua, 10): a 40-year model of the run's 16 towns founds 6-9 (median 7-8; seed a's salt: years 12,
   16, 20, ..., 40), one per round at most, none in the head start round, spread over the decades; a reload at year 16 /
   20 / 28 keeps the gap; deterministic per seed; one founding in a build round with five ready towns, varied
   winners; refunds; readiness; zero growth / NaN / negative growth / the capped scan; pod cadence; the driver glue.
- Not done: site quality before the site search is only "fewer past failures" (the site's score is known after it);
  in game the towns' own seeds differ from the model, so the years will too. Next: TESTING.md "Staggered satellites".

## 52. Downtowns that build up, and empty Works streets (2026-10-14; brief, for a later build; HISTORY.md "203 simulated years")
User, after 203 simulated years on seed `a` (calendar held at 1900): "after a certain point towns should start building up
their downtowns. maybe it's just because the actual game year wasn't progressing while the simulation ran. some sprawling
towns are good, but some others should get dense at some point."
1. **First, test with the calendar moving.** Run Build out with "Move the game date" on, so levels 3 / 4 exist from
   1950 / 1990. Then measure persons per building and the core's levels against vanilla on the same years.
2. **A per-town densify trait.** Seeded, with weights from size, centrality, rail stations and form: about a third of
   towns, never character / deep-forest / hug towns, and few linear ones. Once mature, such a town:
   - adds levels in the core (LEVELS toward the engine's higher weights within a core radius, as far as the API allows
     town-wide weights);
   - fills its core: denser cross streets, smaller blocks, infill of empty core lots;
   - holds outward growth harder than the plain mature hold.

   Sprawling towns stay as they are. Logs: `DENSIFY town= on= why= core= levels= pb=`.
3. **Empty Works and district streets.** 30+ km of empty street in two Works towns (456 and 352 edges, 40 / 37
   buildings). Find who builds them: the mod (OFFSHOOT_HOLD_B should hold), the engine's industry streets, or the dev
   Simulate rounds. Cap them, and log it.
   **Done offline 2026-10-14** (details PLAN.md 6.3 "Held towns"; in game: TESTING.md "Held towns"). Cause, from the
   log: neither the mod nor Simulate built them. The three towns got no mod job after their creation (only the
   Works' 7-edge founding link; every CHECK `needsRoom=false why=open`, no SNAPSHOT / PLAN / SEND), no Simulate step,
   round or fill (`rate=0 class=none`, absent from every round's `per=`). The parents grew by the game's own
   development: East Hornness 222 -> 944 edges with 17 mod edges, Twywath-under-Dun 435 -> 1733 with 53. Their streets
   reached the created towns 1.2 km out (parent r 1225 / 1488 m). ALLTOWN counted them because a town's measure reads every
   street within r + 300 m, plus the connected ones up to 2.5 km whose far node is closest to it. `builtBy` counts only
   that town's own houses, so the parent's housed streets read as empty. The mod-locked edges in the Works' lot area
   stayed at 0 while its lot edges went 13 -> 70, in step with East Hornness' radius passing ~900 m. Aberdart Grange
   had its 107 lot edges at year 40 already. Its parent sat 800 m away and was idle for the 203 years: +13 edges.
   The fix: no mod streets in a held town (a created town below OFFSHOOT_HOLD_B, or any town whose growth is empty),
   no offshoot turn there, and no other town's plan in a held created town's land (send guard). It applies in Simulate
   rounds too. Logged as `OFFSHOOT event=hold why=below|noGrowth|guard:<why>`. Dev ALLTOWN now has `bareLen=`,
   `foreignLen=` and `modLen=`.
4. Tests: a densify town's persons per building rises after maturity while a sprawl town's stays; no densify before
   maturity; created towns gain no streets while empty (done: test_hold.lua).

## 53. Name shapes chosen per map (2026-10-14; brief from names/review/REVIEW_ANSWERS.md; Part A done offline 2026-10-14)
The user asked for a naming review (`names/review/NAMING_REVIEW.md`); the answers are in
`names/review/REVIEW_ANSWERS.md`. The user: "make sure to review ... REVIEW_ANSWERS.md and take that into account". Keep
the big geography cues the user loves; aim for more variation and less forced names. The review's main point: each town
scores stem, generic and affix together, so on a map with a strong survey frames win almost everywhere (run 1729: 11 of
16 framed).

**Part A, now:**
1. **Shapes for the whole map first** (review Q1, Q4).
   - Per language, climate and era, set shape quotas: plain compound, single element, name + separate generic, personal
     name + generic, joined or separate qualifier, frame, saint name, article form, whole landmark name, railroad /
     civic name. Use the review's table.
   - Hand the scarce shapes to the towns with the strongest claim; every other town gets a plain shape.
   - Then fill in the words within each town's shape.
   - Qualifiers (Upper / Lower, Great / Little, North / South) only mark twins: a town with the same base within 3-6 km,
     ideally made as a twin on purpose. A compass word relates to the twin or to a named feature, never to the map edge.
   - Frames (-on-X, -under-X) only on common bases (Newton, Sutton, Stoke …) or a base already used, at most 1 per
     river. -on-Sea once per map, on a sandy resort coast. One saint name in en. Never a bare whole name.
2. **A budget for named features** (Q2).
   - Each named river, peak or lake appears in at most 1 town name per ~6 towns along it, and 2 at most.
   - The strongest claim spends it first: cue weight × how unique the claim is × size.
   - Prefer the river's stem with an ordinary generic (Arunford, Dartington) over a frame.
   - Feature types (a confluence) still go to neighbours as words (Twyford, Forks).
   - Leftover claims go to districts and stops.
3. **Fewer, larger dialect areas** (Q5).
   - 2-3 areas per map, with borders along the main range or river. Celtic on the remote, high or western edge, Norse
     on the coast or in the east, Saxon in the core.
   - About 80 % of names in an area's own dialect. Hybrids only near a border.
   - Celtic elements always come first (Inver-, Aber-, Llan-, Pen-, Bal-).
   - The area also sets the feature words: fell, dale, -water and tarn in the Norse area.
   - US areas follow who settled them: New England English, Mid-Atlantic Dutch / German, French, and Spanish on dry maps.
4. **The review's Q7 hard gates as tests,** over many seeds × site presets × climates:
   - frame and whole-name shares within the quota + 5 points;
   - tokens per name: en ≤ 1.4 on average, usa ≤ 1.8, never 4 or more;
   - a named feature in at most 2 town names;
   - a stem at most once per 12 towns (twins excepted);
   - one dialect per name, or an allowed hybrid;
   - at most 2 feature ideas per name;
   - a compass word only on the right side of its twin;
   - at least 35 % quiet names, a soft target.

Results Part A (2026-10-14, offline; details PLAN.md 6.3 "Name shapes chosen per map"; in game: TESTING.md "Climate-led
names" step 11):
- DONE items 1-4: `PN.planShapes` (shares per language from the review's table, claims, twins, quiet towns),
  `PN.featureGrants`, the dialect areas (`PN.regions` / `dialectAt`), the word and idea limits; `NAMES shapes` line and
  `shape=` on NAME lines; test_shapegates.lua (the Q7 gates) green in full mode.
- The 1729 sites (seed 1): en temperate Seahill, Mytbridge, Cuckmeredale, Lower Glavenmouth, Trefach, Thurtoft,
  Haywater, Ashminster, Oakness, Twyley, Abworth, Llanwyn, Dodmere, Holt, Babton, Kirkby-under-Edge (13 plain, 1 single,
  1 qualifier, 1 frame; was 11 of 16 framed); usa temperate Swanport, Silver Forks, Pine Junction, Lower Turkey Bend,
  Holliswood, Boonefield, Hickory Harbor, Prairie City, Oak Point, Twinville, Russell Prairie, Lyman Flats, Shadydale,
  Ellismont, Morganville, Three Rivers.
- Name lab: gen.js in step with §50 and §53 (check_port 2844 / 2844).
- Not done: leftover feature claims are counted (`left=`) but not yet handed to districts or stops (stops already take a
  river name on bridges); districts' compass words (ot_offname, "East Lyman Flats") are relative to their parent, not
  checked by the gates; the lab's map mode is Part B item 7.

**Part B, next:**
5. **Settlement layers** (Q3). Old, middle and late per town; rivers and peaks keep the oldest layer.
   - Created towns follow the game year: Works before 1920 get Ironbridge-style names; the railway era gets Junction,
     Station and New X; districts after 1945 get Heights, Park, Estates and Acres.
   - No invented "Native-derived" words.
6. **Climate shape tables** (Q6).
   - Tropical: Port X, Xtown, X Bay, X Cay, Estate / Pen / Hall; no -thorpe, -by or -ham.
   - Dry: more weight on water names where there is water, Mesa / Butte, a Spanish layer on usa.
   - Subarctic: Fort X, Landing, Portage, Rapids; Glen, Strath and Kyle in en; vik and fjord in sv / nb.
7. **The name lab** (Q8). Map mode with a rating for the whole set, import of a game log's NAME lines, a shape A/B
   test, ratings by shape, a shape mix view, names drawn on a map, and the Q7 numbers.

The "sounds real" n-gram score (Q7, soft) needs real gazetteer data as scoring data only. It is optional; ask the user
before adding any gazetteer data to the repo.

Results Part B (2026-10-14, offline; details PLAN.md 6.3 "Name shapes chosen per map, Part B"; in game: TESTING.md
"Climate-led names" step 12):
- DONE item 5, layers: `PN.layers` (old 35 % / late 25 %, 30 % from 1900, by size and the crossing / mouth / market claim),
  per-language `layers` forms (en Saxon / Norse / Celtic old, Norman middle, resorts and New X late; usa -ton / -ford /
  Mount / Fort old, -ville / -burg / City / Springs and the personal names middle, Junction / Heights / Park late),
  `layer=` on NAME lines and `layers=` on `NAMES shapes`. Civic names only on late towns away from confluences (the usa
  Junction forms lost their confluence tag). Created towns by the game year (ot_offname ERAS): Works before 1920
  Ironbridge-style / -Works, 1840-1945 Junction / Station / New X, districts from 1945 Heights / Park / Estates / Acres
  (test: en districts 88 % post-war forms in 1965 vs 8 % in 1900; Works 38 % old industrial forms in 1880 vs 24 % in
  1990). No Native-derived words.
- DONE item 6, climate tables (`PN.climateOf`): shares, words, boost, veto, shared groups, saints, areas, the settler group
  per language and climate (en tropical Port / Xtown / Bay / Point / Cay / Estate / Pen / Hall / St X and no -thorpe / -by
  / -ham; usa dry Springs / Wells / Tank, rock colours and the Spanish group on a third of the map; en subarctic Fort X /
  Landing / Portage / Rapids / Narrows / Glen / Strath / Kyle; sv / nb vik / fjord / fell; romance tropical saints).
- DONE Part A item 2's open bit: leftover feature claims (`featureGrants` list, stateless `PN.leftClaim`) go to the
  parent's district first ("Uskford", pattern `feature`) and to the town's first stop away from the water (`claim=`),
  under the feature's budget and the word budget.
- DONE the gates: test_shapegates Part B (the climate's shares and words; tropical no -thorpe / -by / -ham; civic never on a
  confluence and only late; layers by size / site; created towns by year; district compass words on the parent's side;
  leftover claims; the character hook), green in full mode.
- DONE item 7, the lab (Q8): Whole map (plan) mode with the region rating, a game log import (file picker), the shape A/B
  test, ratings with shape and the Export's `byShape`, the shape mix view, the names on a map, the Q7 numbers;
  check_port 3792 / 3792.
- DONE the naming hook for strong characters: `town.character = "<kind>"` (hilltop, harbour, cove, street, company,
  garden, island, market, church; en and usa forms), read by namesAssignGen from `characterOf(t).nameKind`; the
  characters work sets that field (interface in PLAN.md).
- Samples (seed 1, start 1850, 16 towns; districts / Works at 1890 and 1965):
  en temperate: Haythwaite, Swainfield, Barleybridge, Nether Mytton, Wheathall, Thurthorpe, Eamead-in-the-Marsh,
  Seamouth, Mytton, Woodbottom, Trefawr, Holt, Ormmead, Chipham, Eamead, Llanwyn; en tropical: Dodfield, Reef Key,
  Cliffnaze, Content Bay, Leigh, Kilgowan, Hemp Estate, Glavenmouth, St Elizabeth, Whitecliffe, Palmsands, Balmore,
  Wheatchurch, Clay Estate, Port Cay, Carolinetown; usa dry: Graniteboro, Rutledgefield, Agua Dulce, Turkey Falls, Las
  Lomas, Haleton, Otterview, Winslow Flats, Sulphurbrook, Los Cerritos, San Felipe, Clayfield, Pine Hills, Prairieville,
  Whitman Flats, Santa Rita. Districts: Barleybridge Junction (1890), Trefawr Heights, Palmport Acres (1965); Works:
  Forgebrook, Coalville (1890).
- Not done: the "sounds real" n-gram score and a real-gazetteer column in the lab's shape mix (gazetteer data: ask the
  user first); the shape mix's "Review Q1" column shows the review's table instead.

## 54. Strong characters, roundabout town, densify (2026-10-14; done offline 2026-10-14; plan CHARACTERS_BRIEF.md; details PLAN.md 6.3 "Strong characters, roundabout town, densify"; in game: TESTING.md "Strong characters")
User: "identifying more characters with strong preference, like deep forest. these should spawn less often, maybe 1 or
2 on a map depending on how many cities, and should be very distinct and really push the parameters"; "one character
could push roundabouts more"; "lets also build strong characters and roundabout town. lets test all in next iteration".
- DONE **framework** `ot_character.lua`: registry (append-only ids: frame `ck`, map record `cm`), site record (terrain,
  wide survey, features, a ring probe, the nearest heavy / medium industry, era, region), selection once per new map
  (1 per ~8 own towns, 1 below 10, at most 3; one kind once; 3 km apart; no metropolis-sized / created / framed
  secluded town; highest score first, rare kinds x up to 1.3, seeded ties), saved at once and on the frame, stable after
  a reload; old saves get none (`why=oldMap`). Deep forest is the first kind (its own pick and quota, unchanged); the
  secluded towns stay a separate form, never stacked (a kind town is never secluded; the secluded quota passes on).
- DONE **kinds** (8 + roundabout): hilltop, clifftop, harbour cove, waterfront, street village, company town, garden
  city, island town, roundabout town; each with its style, a forced form, knobs within the geometry limits, motif
  preferences, offshoots / levels rules and a naming cue. Skipped: moorland, spa, mountain pass (no reliable site test).
- DONE **roundabout town** (`ot_ring.lua`): one-way rings (square_roundabouts' sizes and ring template, counter-clockwise,
  `junctionConnsDir` configs on every node) at the plan's own new 3-4-way crossings on empty land; never an existing
  node; stripped on a refused pre-check; `RB` lines, PLAN `roundabouts=`; dev showcase "Roundabout town" (RB_TOWN).
- DONE **densify** (§52 item 2): a seeded trait at maturity (~1/3, few linear), saved `dz`; harder mature hold, level
  weights toward 8 persons per building, smaller blocks, core upward doses; `DENSIFY` lines.
- DONE **setting** "Strong town characters" On (default for the test) / Off (13 languages); deep forest unaffected.
- DONE **dev**: Town tab "Force character" (kinds + densify, `CHARDEV`).
- DONE naming hook: `characterOf(t).nameKind` (the names Part B's kinds) and `Driver:characterNameCue(t)`; the picks
  exist before the names phase now.
- Tests: main test_character (21), dev +1 / counts. Open: the in-game run (TESTING.md "Strong characters"), the
  setting's release default.

## 55. Style region setting (2026-10-14; done offline 2026-10-14; details PLAN.md 2.2 "Town style setting"; in game: TESTING.md "Town style setting")

User: "how come our street styles in settings is only auto or american grid? will we eventually be able to choose
between each type? e.g. play american names with european style organic building?"

Done:

1. **"Street style" is now "Town style"** (mod param `style`, 13 languages, new tooltip: Automatic follows the map's
   name list; a region picks the look apart from the names; the site decides within the region's mix, the climate adds
   its bias; names always follow the name list). Values appended, so saved indices 1 Automatic and 2 North American
   grid keep their meaning: 3 European organic (EU), 4 Mediterranean (MED), 5 Nordic (NORDIC), 6 North American
   suburbs and grid (US, the regional mix), 7 East Asian (EAST_ASIA), 8 Japanese (JP), 9 Mixed (MIXED).
2. **North American grid stays** the forced single style (`forceGrid` -> `forceStyle = "NA_GRID"` in the driver);
   its region still comes from the name list, exactly as before.
3. **The chosen region drives every region bias:** `ot_inputs.build(raw.styleRegion)` sets `region`
   (`regionSource=setting`), so `ot_site.REGION` style weights, `ot_metro.REGION` variants and `CORE_GRID`,
   `ot_style.pickProfile` and, in preRunFn, the vanilla street angle (`ot_angles.region(s, styleRegion)`, "Vanilla
   town street angles" Automatic) all follow it. The climate bias still multiplies; the site still decides.
4. **MIXED**, a setting-only region: every style weight 1 in `ot_site.REGION`, all metro variants 1, core grid 0.45,
   angle 25.
5. **Names don't change:** `inputs.nameRegion` keeps the name list's region; the driver's `nameCls` reads
   `self.nameRegion` (was `self.region`). The name list's country rides along only into its own region.
6. **Log:** `INIT ... region=<x> regionSource=setting|nameList|climate` and the preRunFn `ANGLE ... regionSource=`.
7. **Tests:** `test_style_region.lua` (every saved index parses, old index 2 unchanged, each region's weights match
   its table with the climate bias, metro / core grid / angle follow, names unchanged by the setting).

Open: the in-game check (TESTING.md "Town style setting"). No Russian or pan-Asian value yet (RU / ASIA stay
name-list only); add them by appending if players ask.

## 56. Roundabout variety and organic ring roads (2026-10-14; done offline 2026-10-14; details PLAN.md 6.3 "Roundabout variety and organic ring roads"; in game: TESTING.md "Combined test iteration" step 1)

User on the showcase run `2026-10-14_2150_sqot-dev` (shots img_2 EU organic, img_10 EU ext roundabout, img_11
Roundabout town): "eu organic looks strange with the big equal circles on the outside"; "roundabout town - it would be
nice if there were different sized roundabouts used. also, roundabouts shouldnt be limited to just that roundabout
town. roundabout town just should use more of them. e.g. perhaps a pair of round abouts added at same time on opposite
parts of a city, or street, for a unique intentional effect."

- DONE **A. Organic ring roads**: for new towns (frame `og = 1`; towns framed before keep their plan) the grower's rings
  wobble per spoke and are spaced unevenly (no two consecutive gaps alike), the ring road's radius wobbles round the
  town, crescents run on an outward curve, the grower's ring beside the ring road is left out (one ring there), the
  secondary radials onto the rings are spaced irregularly; ring arcs, ring road pieces and crescents only within 160 m
  of a street with houses (`ringHeld=`); the EU extension outer zone blends in over 1.5 x ringEvery. MED hill, EU
  extension, garden city and metropolis radial variants share the geometry (half the wobble at gridness 0.8).
- DONE **B. Sizes**: mini R 17, s R 19 / 24, m R 34 / 39, l R 49 / 59 from square_roundabouts' radius list (R 17 is its
  smallest with the one-way small street), by the crossing's class (minor / one main / main x main / gateway or wide),
  smaller ones when the room is short; one-way, `junctionConnsDir` configs on every node, never a live junction.
- DONE **C. Rings in all towns**: every town at its era / region rate (France 0.16, EU 0.09 ... US 0.02, JP 0.015; none
  before 1940, rare to 1960, full from 1975; none in JP dense towns; 2 a plan, 4 a town, 260 m apart); the roundabout
  town at 0.95 / 0.5 with gateways and up to 4 a plan; pairs (two ends of one street, or opposite sides of the town)
  both or neither, the same size (`RB event=pair`); no ring whose crossing or arm ends lie more than 200 m from a
  street with houses (`emptyArm`); a refused ring still sends the plain crossing.
- DONE **D. The roundabout town's empty loops and zig-zag leads**: its strong cross arms ran ~1 km ahead (arm fill lead
  2 blocks of 121 m + the 400 m lead limit, the showcase forcing increments): deep-arm back rows closed empty rectangles
  and the spine with its lanes made the zig-zags (`emptyLen` 2 -> 7 km). Now a housed front of 1.25 blocks, no deep-arm
  back rows, the NA grid variant's lattice 3 deep.
- Logs: `RB event=ring size= R=`, `RB event=pair`, PLAN `roundabouts=` / `ringHeld=`, ALLTOWN `roundabouts=`.
- DONE **Follow-up (sizes and pairs)**: m / l never came offline (every main crossing at the frontier read as a gateway
  -> l, which fell back to s on short plan edges). Now a gateway with one main arm is m (two: l), and a ring's arms are
  extended through the plan's plain continuation nodes (merged into one edge, never through a junction or an existing
  node) before the sizes are tried. Deferred pairs: a ring alone may reserve its partner along its street, saved on
  the frame (`px py ph pr pn`), placed in a later plan of the town or lapsed after 4 (`RB event=pairWait`, `RB
  event=pair deferred=true`). Offline (8 fixture towns): roundabout towns mini 12 / s 24 / m 25 / l 8, of the main x
  main / gateway rings m 68 %, l 22 %; 9 pairs (4 deferred); ordinary EU towns mini 24 / s 7 / m 3 / l 4.
- Tests: main `test_rings.lua` (18). Open: the in-game check (sizes, pairs, ordinary towns' rings, the EU organic outer
  rings); rings below R 17; a ring reserved in the master plan (parallel streets kept off its footprint).

## 57. Roundabout town hubs (2026-10-14; done offline 2026-10-14; details PLAN.md 6.3 "Roundabout town hubs"; in game: TESTING.md "Combined test iteration" step 1)

Evidence: showcase run `2026-10-14_2237_sqot-dev` load 1 (Blank Slate, 2060, 20 increments; img_3 EU organic, img_16
Roundabout town, img_19 Shape: cross, img_0 Metropolis: radial), loads 2-4 (seed `a`: europe 1900, usa 1960, usa dry).
Kept: EU organic's big equal circles gone; one-way rings with no refusal (Roundabout town l R49 + s R24 + s R19, Shape
twin mini, Shape cross m R34, Metropolis radial m R34); no errors.

Causes:
1. **Few rings in the roundabout town** (3 in 18 increments, 6 candidates; seed-a usa: 0 in 14 plans of an NA grid
   roundabout town): rings came only at the plan's own new crossings of 3-4 new streets, and its increments (4-12
   edges, mostly small streets, organic or grid) rarely make one; the ring share hardly mattered.
2. **No pairs**: an in-increment pair needs two such crossings in one plan; ordinary towns drew at 0.14 (7 draws, none
   came), and a deferred pair needed a major crossing ring first.
3. **Empty snaking roads / combs** (Roundabout town north-east / south-west, PLAN `emptyLen` 1.1 -> 4.8 km; Shape cross
   west / south): the showcase forces increments regardless of demand, and forced plans skipped the own empty budget
   (PLAN `ownEmpty=-`). The distance limits (housed front, lead limit 400 m) measure from any street with a house, so a
   road with a house or two near its tip moved the front out each forced step.
4. **EU organic**: the east rectangle is not an outer zone (a forced style has none, STYLE `outer=-`): the 2060 grid look
   (0.59) straightened the whole organic plan (gridness 0.71), so the part grown last (east) came out as a lattice. The
   thin south-west fingers are cause 3.

Done:
- **A. Ring hubs** (`ot_ring` `RG.hubSites` / `RG.addHub`, roundabout town only, `RG.TOWN.hubs`): on its new streets (a
  continuation node of two new edges, or a long new edge's middle, split) the town adds 1-2 new arms across the street
  (each clear of other streets and nodes, its end near houses, a gentle grade) and puts the ring there in the same plan;
  250-450 m (seeded) from every other ring; up to 2 a plan; sized by the street: l at a gateway on a main / medium
  street (roomy gateways first), m on a main street (a medium one half the time), s / mini on branches; no ring fits:
  the arms come out again. Grower-free (organic and NA grid). Every new node is a plain new node (a config in
  ot_proposal.build), never an existing one; -0 normalised; a refused pre-check strips hub and ring (the plan as it was).
- **B. Pairs**: a hub reserves its twin at 0.6 (`RG.TOWN.pair`): along its street (outward) or across the town
  (`kind=opposite`, a new additive frame field `pk` = 2), waiting 6 plans (`RG.PAIR_WAIT_HUB`); a later plan places the
  twin at a candidate crossing in the window or plants a hub there, the same size first. Ordinary towns: still a draw
  per pair, `PAIR_K` 1.5 -> 2 (EU 0.18, France 0.3 max).
- **C. Forced increments keep their empty limits** (`D.FORCED_EMPTY`): the own empty budget (floored at
  `core.OWN_EMPTY_MIN` edges, so a forced step still builds) and a sparse-street hold (`ot_select SPARSE`: in a town with
  1.2 km+ and 10 %+ unhoused street and 3+ houses per 100 m on the whole, no piece among streets carrying under 1.5 houses per 100 m within 150 m; motif
  pieces too). Demand-driven plans unchanged (their own empty budget already holds).
- **D. Look zone** (`ot_style LOOK_ZONE`): an organic town with the organic ring geometry and a grid look above 0.35 keeps
  0.35 in its core; the rest (at most 0.5) comes as an outer zone of its own style from 320 m, blended over ZONE_BLEND
  (gridness 0.55 core -> 0.65 beyond ~725 m at 2060; was 0.71 everywhere).
- **US rings**: the late rate rises to 0.05 by 1995 (`RG.RATE_LATE`, Oceania 0.1); log rates with 3 decimals.
- **Logs**: `RB event=hub size= R= wanted= gate= street= arms= split= partner= reserved=`, `RB event=ring ... hub=
  fell=` (why the larger sizes failed), `RB event=pairWait ... kind=`, `RB event=pair deferred=true kind= hub=`; PLAN
  `sparseHeld=`.
- **Characters and densify** (coordinator, the seed-a loads): load 2 had no pick (every town `applied=no:low`): the
  probe's exact bay pattern failed every lake town, the garden city ramp from 1900 halved its scores at a 1900 start,
  the river town read its river at 250 m (limit 220), and the island's shore trace did not close. Now harbour cove from
  the coast reading (coast share 0.45+, steep: p95 slope / wide relief / rough share; the probe's bay pattern x1.15,
  open water on the 300 m ring rules it out), garden city ramp 1895-1905 with a floor, waterfront to 320 m, an island
  from the wide survey (12+ wet rays) at a lower score, hilltop rise 20 m / 10 directions; the roundabout town a floor
  and a pick weight x1.5 (`CH.KIND_W`) so the coast kinds don't crowd it out (load 3's pick kept). CHARACTER town lines
  list every kind (`top=` all, `whys=`). Densify: `DZ_P` 0.33 -> 0.45, shore 0.85, fingers 0.8, sprawling 0.7, clustered
  1.25, radiating 1.15 (load 2's drawn towns p 0.13-0.16 -> ~0.33; the map's form mix ~32 %).
- Tests: `test_hubs.lua` (7: rate EU / NA grid, sizes, pairs, ordinary towns and a crowded hub, the saved kind, US
  rates), `test_forced.lua` (4: forced plans' empty limits for the roundabout town and EU organic, the sparse rule, the
  look zone), `test_character.lua` (+3 replays: seed-a europe 2 picks of different kinds, its densify rate, seed-a usa
  1960 keeps the roundabout town).

Offline numbers (quick mode; `--full` in brackets): roundabout towns EU 28 rings in 36 plans (50 in 72), NA grid 19 in 36
(41 in 72); sizes over both mini 21 / s 19 / m 6 / l 1 (42 / 34 / 11 / 4); 8 pairs of 11 reserved (14 of 23). Forced
plans with houses lagging: unhoused street 2.4-6.4 km -> 0-1.8 km (roundabout town), 2.0-9.5 km -> 1.1-1.5 km (EU
organic), every new point within the lead limit.

Open: the in-game check (TESTING.md step 1); l stays rare offline (gateways crowded by the plan's own streets, `fell=`
will show why in game); the look zone is the EU organic grid block's likely cause, not proven (no graph dump of the
run).

## 58. The mod's level weights hold grown towns low (2026-10-15; done offline 2026-10-15; run `2026-10-14_2347_sqot-dev` load 3; details PLAN.md 6.3 "LEVELS by maturity"; in game: TESTING.md "Combined test iteration" step 7)
Seed `a`, europe list, start 1950 (calendar not moved), Quick 40 years; 0 errors; 2,016 -> 12,839 buildings. Character
picks worked: harbour_cove (Brynchurch Cove, 0.85) and garden_city (Ashminster Garden City, 0.73).

ALLTOWN at year 40, `lvl=a:` (actual share per level) and `w:` (weights in force):
- **Towns where the mod sets weights stay low.** pb 2.75-3.39:

  | Town | Buildings | Actual levels | Weights in force |
  |---|---|---|---|
  | Edton | 699 | 100/0/0/0 | 100/0/0/0 |
  | Trefach | 679 | 99/1/0/0 | 98/2/0/0 |
  | Abercoed | 859 | 80/20/0/0 | 80/20/0/0 |
  | Dart Head | 1,241 | 86/14/0/0 | 84/16/0/0 |
  | Mytham | 1,388 | 62/27/10/0 | 56/32/12/0 |

- **Towns the mod leaves alone (`c:-`) build up.** pb 4.0-5.0, level 3 at 22-38 %: Milton-under-Edge, Hornness,
  Winmere, Shaw, Kelington.
- The engine's own weights (`u:`) are about 34/27/22/17. So the mod's level weights override the engine toward level 1
  even for towns of 700-1,400 buildings. They work against the user's wish that towns "start building up" later.
- Densify never triggered for an ordinary town. Its draw only runs once a town reads mature; in 40 years only 4 towns
  drew (all character or deep-forest, excluded).

The user (after 203 years): "after a certain point towns should start building up their downtowns". The user earlier:
"I like that the towns branch out a lot early on, and in later years start building up, but not before".

Open:
1. Rework the LEVELS policy by maturity:
   - young towns: hold low (as now);
   - from about half-grown: hand back toward the engine's weights;
   - mature: at or above the engine's weights;
   - densify towns: above them.

   Never hold a town of 600+ buildings at 100 % level 1.
2. Draw densify earlier: from half-grown, with the effect ramping in.
3. Measure against the unmanaged towns in this run: pb 4-5 at the same size.

**Done offline 2026-10-15** (details PLAN.md 6.3 "LEVELS by maturity"; in game: TESTING.md "Combined test iteration"
step 7). Causes, from the log:
- **LEVELS never sent those weights.** Every LEVELS line of load 3 reads `ours=0`. The custom weights appeared and
  changed only in step with the mod's FILL restores (makeTownSetInitialLandUseCapacitiesCmd after a dose's DevelopAt).
  The 5 towns restored in year 1 got weights by the year-1 read, Edton after its first restore, and every later change
  followed a restore. The towns never restored kept `c:-`. Rows like `0.453303/0.255125/0.100228/0` are no editor's.
  They were read as the player's (`skip=player`), so LEVELS never ran on them. "The towns the mod leaves alone" are the
  towns no FILL restore touched. Inferred (no restore without a dose to tell the two commands apart):
  docs/findings/towns.md.
- **The dev Simulate's pool drivers had no baseline and no saved state.** Their checks classified every town without
  the baseline and drew no densify (the frame read nil). All 4 DENSIFY draws came after `SIMGROW stop`.

Built:
- **Owner `fill`** (`UP.levelOwner`, `UP.editorLike`): weights that are none of ours, not the baseline and no town
  editor's (the editor writes rows normalised to 1, or slider steps of 0.01) count as the engine's write. LEVELS may
  replace them. A player's (editor-like) weights stay untouched in every phase.
- **Phases** (`UP.levelPhase`, by `UP.levelMat`: maturity from persons, or from buildings 200 .. 800, the larger):
  - **young** (under 0.5): unchanged;
  - **blend** (0.5 .. 0.9): a tilt toward level 1, -1 easing to 0 in quarter steps. It is never lower than the town's
    current weighted target (`UP.share1`): a town at the engine's own weights gets none;
  - **mature**: the engine's own weights (the fill weights cleared; `LV_MATURE_K` 0 from 1950), and before 1950 the
    old pb tilt (levels 1-2 only);
  - **densify**: above the engine's from the draw, ramping to full at 0.75 (`DZ_RAMP_MAT`), at least `DZ_K_MIN`.

  So a town of 500+ buildings is half grown, and never held at level 1 alone.
- **Era** (`UP.eraTop`): a level above the era's top gets the top's weight (levels 3 / 4 from 1950 / 1990).
- **Refill** (`Driver:levelsAfterRestore`): after a FILL restore, a town past young whose weights the mod sent gets
  them back at once (`LEVELS event=refill`).
- **Saved**: frame `lw` is now the signed tilt x 4, plus `ls`, the sig sent (additive; old `lw` 1..4 still read as
  ours).
- **Densify**: drawn from half grown by the same level maturity. The pool drivers read the root's saved state and
  baseline (`savedNow`, `levelBaseOf`). The hold ramps in from the draw (`CH.dzRamp`).
- **Logs**: `LEVELS town= action= phase= why= owner= buildings= pb= mat= matL= tilt=<from>-><to> era= from= to= base=
  lvl=`, `LEVELS event=refill`, and debug skips with `phase=` / `matL=`.

Offline (test_levels58, a fit of the run's 16 ALLTOWN rows: persons per building 2.73 / 4.22 / 24 at levels 1 / 2 / 3;
the target's shares, not the slower buildings):

| Town (year 40) | Buildings | pb in 2347 | Phase | pb target | Densify |
|---|---|---|---|---|---|
| Mytham | 1,388 | 3.39 | mature, cleared | 4.89 | 6.17 |
| Dart Head | 1,241 | 2.95 | mature, cleared | 4.89 | 6.60 |
| Lower Aberarun | 1,058 | 3.05 | mature, cleared | 4.89 | 6.60 |
| Abercoed | 859 | 2.78 | mature, cleared | 4.89 | 6.60 |
| Oakhaven | 761 | 3.69 | mature, cleared | 4.89 | 6.17 |
| Edton | 699 | 2.75 | blend -0.25 | 3.88 | 6.03 |
| Padfield | 682 | 3.38 | blend -0.25 | 3.98 | 6.04 |
| Trefach | 679 | 2.79 | blend -0.25 | 3.88 | 6.05 |
| Milton-under-Edge / Hornness | 878 / 721 | 4.70 / 4.51 | mature, untouched (`c:-`) | 4.89 | 6.17 |
| Winmere | 530 | 4.03 | blend, untouched | 4.69 | 5.07 |
| Wemmead / Shaw / Kelington | 483 / 300 / 295 | 4.48 / 5.00 / 4.33 | young, unchanged | | |

Densify share on this map's 13 ordinary towns, by their logged sizes: 3 drawn by year 20 (4 % on expected), 8 by year 28
(16 %), 10 by year 40 (22 %). It stays a third of the towns drawn, but it is short of "a third of the ordinary towns by
year 20-30". The map is linear-heavy (`DZ_FORM` linear 0.3), and only 8 of the 13 are half grown by year 28. Raising
`DZ_P` would break the third of the drawn on other maps (test_character), so it was not done.

Tests: test_levels58.lua (new, 10: the replay, owners, young unchanged, player never touched, the era gate, the densify
ramp and share, the driver's LEVELS / refill / pool-driver reads). Changed: test_demand / test_round0502 level tests
(their 1900 world: `top = 2`; 600 buildings now read half grown), test_character (a grown town at pb 5 at maturity
0.95; 0.8 is still in the blend).

Open: the in-game run (TESTING.md step 7). Two things are unverified: that the refill holds against the restore's write
(if the engine writes the weights on every restore, the refill adds one command per dose), and the persons per level-3
building (24 is one run's fit).

### 57b. Round 2 after the in-game run `2026-10-14_2347_sqot-dev` (2026-10-14; done offline)

In game: hubs built (Roundabout town 5 rings: 1 l R49 at its centre, 4 s), EU organic's grid block gone, empty leads
much reduced, no errors. Still off, and why:
1. **4 hubs in 20 steps**: the game's plans had 1-9 edges (the own empty budget's cap, PLAN `ownEmpty=1335/11` ...
   `/4`), mostly small streets: almost no continuation node of two new edges or edge of 92 m+, so almost no hub site
   (all four were `street=medium arms=1`). Offline plans had 14-24 edges.
2. **Sizes fell back** (3 of 4 wanted l, got s: `fell=59:nearNode,...` / `nearNew`): a hub tried its sizes downward at
   one fixed spot.
3. **No twins**: the ring call's `canDefer` needed a frame in `self.saved`; the first hubs came before the frame was
   saved (SAVE event=frame at line 1178 of the log, the hubs at 1104), later ones had none readable either: never
   `pairWait`.
4. **Empty roads**: EU organic's long lead west with a cross at its end is the satellite seed (`SATELLITE town=8785
   kind=seed site=-2054:4376 link=432 coreEdges=3 why=quota`: the map's staggered hamlet, by design; it fills later);
   its south-east "ladders" match the culdesac_pods motif (collector 327 / 437 m toward 306 deg, closes 2 / 3, 30-37
   houses). The Roundabout town's south-east roads could not be traced from the log (no positions per piece): the cross
   arm at 336 deg or the village green triangle (ring 269 / 838 m, 402 m out) are the candidates. PLAN now logs
   `origins=` (metres by source: arm, m:<motif>, ring, crescent, link, plain, and the farthest new point from houses
   with its source), so the next run tells.
5. **Refused pair at Shape fan** (`RB event=refused rings=2 msgs=Collision collisions=4`): the log has no DIAG lines for
   it. The second ring had fallen back to s on `nearNode`; the clearance measured existing streets by their chords
   only, so a curved existing street could bulge into the ring: it now checks the Hermite curve too (`nearCurve`), and
   the refused line logs each ring's room (`near=x:y:R:node=..:street=..`).

Done:
- **Dead-end hubs** (`RG.deadEndSites` / `RG.addDeadEndHub`): a dead end of the town's streets near houses (up to 40 a
  plan) gets its street carried on to a new crossing with the arm on and 1-2 across (the stem plus 2 at least); the
  planner's own kind of join (a dead end; never a junction), every other node new, configs from ot_proposal.build.
- **Sliding, not shrinking**: a hub tries only its class's sizes (`exact`); a dead-end hub's centre slides out along its
  street (R + 32 / 52 / 76 / 104 m) until the ring has room; street sites need the class's room round them; no spot for
  the class: the next class down. The wanted class is drawn: l 0.2, m 0.35, s 0.3, mini 0.15 (`RG.HUB_MIX`).
- **Spread**: sites farther from the centre rank first; the gap between rings 220-400 m (was 250-450); up to 2 hubs
  and 14 tries a plan.
- **Twins**: `canDefer` always (kept in memory, saved on the frame when it exists); a twin's hub may also be a
  dead-end hub in its window.
- Ordinary towns: unchanged (rates, no hubs).
- Tests: `test_hubs.lua` +1 (small plans of 5 edges: 0.86 rings a plan, 43 dead-end hubs; full 0.95, 97); the ring
  checks accept a hub's join at a graph dead end.

Offline (quick; full in brackets): EU roundabout towns 40 rings in 36 plans (75 in 72), NA grid 31 in 36 (53 in 72),
small plans 62 in 72 (137 in 144); sizes mini 15 / s 26 / m 23 / l 7 (22 / 49 / 46 / 11); 10 pairs of 14 twins
reserved (18 of 27).

### 57c. Round 3 after the in-game run `2026-10-15_0234_sqot-dev` (2026-10-14; done offline)

In game: the Roundabout town 20 rings in 20 steps (l 7, m 5, s 6, mini 2), all hubs, spread over the town; it reads
as a roundabout town. Kept as is. Leftovers, and why:
1. **Rings at the edge with empty arms** (a mini alone bottom-left, an l at a road's end bottom-right): a dead-end hub
   took any dead end within 170 m of a housed street's midpoint and slid out to R + 104 m, so a ring could sit ~300 m
   from houses with only its arm ends checked (200 m).
2. **EU organic's empty outer loop**: its wedge frame (`FRAME town=7041 outcome=built kind=wedge edges=35`, ot_wedge:
   linear shape), not the grower, the crescents or the ring road (the town's own plans were 12 edges of
   ribbon_village in 3 steps, then empty). The frame links tips that lie within 250 m of houses with straight streets
   up to 280 m long, so a link ran on through empty land; the ring lead (160 m) never applied to frames.
3. **Twins lapsed** (12 reserved, 2 placed): mostly `why=none`, no site in the window: a street twin looked only
   outward along its street, beyond the houses (the hub filter keeps sites among houses); the across-town ones failed
   on `hub:nearNode` / `nearStreet` at the few sites in a 30 deg window.
4. **`origins=` is logged** on every PLAN line of a planned increment (609 in the run, 22 in the Roundabout town); it
   sits near the end of the ~870-character line. The frame stage writes FRAME lines, not PLAN.

Done:
- **Hubs among houses**: a dead-end hub's dead end within `HUB_DE_HOUSED` 80 m of a housed street and with
  `HUB_DE_HOUSES` 6 buildings on the streets within 120 m (`RG.housesNear`); every hub's centre within
  `HUB_CENTRE_LEAD` 140 m of a housed street; its arms within `ARM_LEAD` 200 m as before.
- **Frame links held to the ring lead** (`ot_wedge.frameStreets` `ringLead` = `ot_select.RING_LEAD_M` 160 m, every
  point of a link or tail; wedge and meadow frames). Trade-off: in `test_bigform` the fingers town's frames come later;
  its wedge share at 10x growth is 0.34 against 0.35 without wedges (the test's 0.05 margin kept at 5x and for the
  linear town; at 10x the fingers case now only asks for no more than without).
- **Twins**: a hub twin along its street looks both ways (`pk` 1 now saved too), the window 40 deg
  (`PAIR_HUB_ALIGN`), waiting 8 plans; a placed twin's line says `why=-` (it said `none`).
- **Ring count fixed**: `RG.existing` grouped one-way edges by 90 m from a first edge, which split an l ring (R 49 / 59)
  in two for the spacing and the cap; it now groups them by their shared nodes.
- Tests: `test_hubs` (+1: dead-end hubs only where houses are; every hub centre within the lead; twins mostly complete),
  `test_forced` (+1: a frame link through empty land waits), `test_bigform` (the margin above).

Offline (quick; full in brackets): EU 34 rings in 36 plans (63 in 72), NA grid 27 in 36 (49 in 72), small plans 61 in
72 (128 in 144); sizes mini 17 / s 27 / m 14 / l 3 (24 / 50 / 32 / 6); twins 12 placed of 12 reserved (21 of 22).
Not looked into: EU organic's own plans went empty from step 4 (`reached=14 blocked=4-5 excluded=14-16`), so the
showcase stopped it after 7 steps; the rest of its growth was the game's.

## 59. Forest era, stall fix (2026-10-15; done offline 2026-10-15; runs `2026-10-14_2237_sqot-dev` load 2 (seed `a`, 1900), `2026-10-14_2347_sqot-dev` load 3 / `2026-10-15_0234_sqot-dev` load 2 (seed `a`, 1950), `2026-10-15_0234_sqot-dev` load 1 (showcase); details PLAN.md 6.3 "Forest era, stall fix"; in game: TESTING.md "Combined test iteration" step 8)

The user: "can we change early towns that weave through to be slightly higher weighted. and yes lets soften era
curve". Earlier: "building around forests is really cool, let's keep pushing this"; "environmental cues continue to be
the most interesting thing".

**1. Forest era.** Seed `a`, STYLE `forest=<cover>:<mode>`: start 1900 9 hug / 6 clear / 1 deep, start 1950 3 hug /
13 clear / 0 deep. The draws replay exactly offline: a town's seed is `rng.seed(id, x, y)` (positions from its NAME
line), the same 16 towns at both starts, so u is the same and only p differs. The 1950 drop is two things:
- the era factor (0.63 at 1950 with the old curve);
- the style mix, which counts for more: at 1950 ten of the 16 towns resolve to planned or grid styles (4 EU
  extension, 2 NA suburb, 2 NA grid, superblock, ensanche) against 4 at 1900.

Built (`ot_forest`):
- hug odds: x`EARLY_F` 1.12 up to 1910, back to 1 by 1930;
- full strength to 1950, `ERA_LATE` 0.5 from 1990 (was 1 to 1920, 0.25 from 1980);
- deep forest full to 1960, 0.45 from 2010 (was 1930 / 1990 / 0.35);
- unchanged: P_MAX 0.95, the style / tier / character factors, and the planner's hug rules (the some-houses-in-the-forest
  balance);
- forest lanes keep their early odds (`min(1, eraF)`), but get more 1950-1990 lanes from the softer curve (1960, per
  eligible crossing: hug 0.45, was about 0.26);
- STYLE lines log `forestWhy=` (the draw's p, factors and u).

| Seed `a` replay | hug | clear | deep |
|---|---|---|---|
| 1900, before | 9 | 6 | 1 |
| 1900, now | 11 | 4 | 1 |
| 1950, before | 3 | 13 | 0 |
| 1950, now | 4 | 11 | 1 (Milton-under-Edge: p 0.95, u 0.94) |
| 2020 (the 1950 styles) | 2 | 14 | 0 |

The 1950 target (8-9 hug) is not reached with the style factors as they are. The only towns left to turn are planned
styles: 60256 / 60258 EU extension (u 0.60 / 0.51 at base 0.45), 60268 / 60269 NA suburb (u 0.78 / 0.82), 60263 NA grid
(u 0.33 at 0.1). EU extension 0.45 -> 0.62 would give 1950 6 hug + 1 deep, but also 1900 12 hug + 1 deep. That is a
style decision, so it was not made.

**2. The stall.** Showcase EU organic (town 7041, linear, 2020): steps 1-3 built only motif pieces (`origins=m:ribbon_village`),
then from step 4 the plans were empty (`reached=14 blocked=4-5 excluded=14-16`, `force=true`). The empty PLAN line
named no hold, so the cause comes from the code and a replay, not from the log:
- `limits.sparse` (§57) holds every piece that starts, ends or runs among streets with under 1.5 houses per 100 m;
- a growing town's dead ends sit on its newest, emptiest streets (the ribbon's far end, the game's new stubs);
- the strong-arm envelope keeps the plain pieces near the core;
- so every candidate was held. It is a hard limit with no relaxation, and four empty plans stopped the town.

Other suspects:
- the forced-plan own-empty budget: not the cause (`ownEmpty=515/-`, no cap);
- `ringHeld`: 0 in every plan;
- frame holds: no frame stage before step 7;
- the lead limit: at most 1 piece held;
- the look zone: shapes geometry and holds nothing.

Replay (`test_forced`, a round core, EU organic 2020 linear, the showcase's house counts 185 -> 680 arriving from the
core outward, forced plans with the sparse limit): the first plan comes out empty in each of 4 towns, all its pieces held by the sparse hold and the envelope
(7041: `held=sparse=30,env=22`).

Built:
- **Starve relaxation** (`ot_select.SPARSE_RELAX_EDGES` 4): when the hold would leave the increment under 4 edges, the
  held pieces come, the cheapest first, up to 4 edges; the lead limit still holds. PLAN `sparseRelax=true`. Replay: no
  empty plan in 4 towns (each was 0 at step 1), 1-2 relaxed plans each, at most 4 edges, the farthest new point
  168-223 m from houses (lead 400).
- **Logs**: the empty PLAN line has `held=` (every hold's count, now including the shape's limits: env / armFill /
  armFront / wide / front, counted in ot_select), `emptyRun=` (empty plans in a row, reset by a build) and `forced=`; the
  job's why ends `held:<top>`. A `STUCK` line (also without debug) after 6 empty plans in a row, then every 10.
- **Demand play**: the sparse hold never applies there. Its hard limits (lead, ring, wedge, meadow) all ease as houses
  arrive, and an empty plan only sets a cooldown. Test: a town whose dead ends all lie past the lead limit plans 0
  edges with `held=lead=19`, then 8 edges once the houses reach them. In the showcase, 7041's later demand builds went
  to its satellite seed (8 edges) and its wedge frame (35 edges); no normal demand plan ran after the stop, so that path
  is unverified in game. One stall stays possible: a town whose own streets never get houses keeps its own-empty cap
  at 0 until the game's streets grow its length (budget 1.5 km + 8 %); the STUCK line will show it (`held=-`,
  `ownEmpty=<m>/0`).

**3. Frames vs wedges** (`test_bigform` fingers: wedge share at 10x 0.34 vs 0.35 without wedges since §57c). Logged
during the run: the held links were nearly all held by their own far tip (160-250 m from houses, the link no farther out
than that tip), not by a stretch through empty land. A link bent in toward the centre never fit (the tip itself is
past the ring lead), so that idea was dropped. Built (`ot_wedge`): a link up to `FAR_LINK_M` 160 m long comes when no
point of it lies farther from the houses than its farther tip + `FAR_SLACK_M` 15 m. Long links and tails keep the
ring lead, so the §57c test case (a 222 m link to a tip 244 m out) still waits.

| test_bigform, 10x / 5x wedge share (without wedges 0.35 / 0.31 for fingers) | fingers | linear | radiating |
|---|---|---|---|
| §57c | 0.34 / 0.24 | 0.51 / 0.36 | 0.32 / 0.33 |
| now | 0.28 / 0.25 | 0.49 / 0.33 | 0.32 / 0.34 |

The 0.05 margin at 10x is restored for every form. Trade-off: short frame links to tips up to 250 m out are back, so
part of the empty edge in the 0234 frame can return (short pieces only, never farther out than the game's own tips).

Tests:
- test_forest +1: the seed `a` replay (it first reproduces the game's 32 draws under the old odds), and the era curve
  checks;
- test_deep: the late year 2015 (1995 still goes deep fairly often);
- test_forced +3: the stall replay, demand recovery under the lead limit, `heldText`; the frame test +1 case (a short
  link between far tips);
- test_bigform: the margin back.

Open: the in-game run (TESTING.md step 8). Also the 1950 hug count, if the user wants more than 4 + 1 deep on seed
`a` (that needs the planned styles' factors).

## 60. Literal, context-aware names first, a little national flavor (2026-10-15; done offline 2026-10-15; details PLAN.md 6.3 "Literal, context-aware names first"; in game: TESTING.md "Combined test iteration" step 9)
The user, after run `2026-10-15_0341_sqot` (seed `a`, europe, 1950):
> "did one of our naming phases reduce the geographically aware names, at least for european? i don't see as much now.
> it seems like more of the made up names, like mytham, which i'm not fond of. i think more literal representation of
> surrounding it more fun, and maybe some european flare mixed in. actually, maybe we just really push the simple context
> aware naming and then just a little nationality mixed in."

Yes, §53 Part A did this:
- the per-map shape plan gives about 40 % "quiet" names, with no terrain word on the weakest sites;
- it fills plain compounds from dialect stems: personal names and old morphemes (Myt-, Twy-, Swain-, Thur-, Kel-, Wem-, Ed-, Pad-, Ulf-, Ac-).

That followed the naming review's push for gazetteer realism. The run's names:
- **opaque:** Mytham, Shaw, Padfield, Kelington, Edton, Wemmead, Trefach, Abercoed;
- **liked kinds, from earlier runs:** Lower Arunmouth, Dart Head, Oakhaven, Hornness, Middle Fork, Fellhaven-under-Dun, Oakhaven-on-Blackmere.

Direction:
1. **Descriptive first.** Most names should be built from readable words for what is actually at the site:
   - trees: Oak-, Ash-, Birch-, Elm-, Willow-;
   - water: -brook, -ford, -mere, -water, -well, Mill-, -bridge;
   - land: Hill-, Stone-, -dale, -combe, Moor-, -field, -wood, Fen-;
   - coast: -haven, -cliff, Sand-, -ness, Sea-;
   - human marks: Market-, Church-, Mill-, Bridge-, Cross-;
   - the named features: river, lake, peak.

   For example Oakbridge, Stonebrook, Millford, Ashcliff, Fenwater, Arunford.
2. **Quiet names rare:** about 10 %, and readable when they occur (Newton, Middleton, Kingsbury), not opaque morphemes.
3. **Nationality flavor as seasoning,** about 1-3 per 16 towns:
   - a dialect form that stays readable or carries a real feature (Aberarun with its river, a Norse -by / -thwaite, a Welsh Llan-, Kirk-);
   - opaque personal-name stems at most 1 per map.
4. **Keep:**
   - the big geography cues;
   - whole names (Middle Fork, Three Rivers, Dart Head);
   - qualifiers tied to features (Lower Arunmouth);
   - character names (Brynchurch Cove);
   - the word budget and no-repeat rules;
   - the climate fit and survey agreement.

   Relax the review's shape quotas so cue-bearing shapes (whole, qualifier, frame on a feature) can reach about a third of towns, as long as they are not repeated.
5. **Every generator language gets the same rule:** readable descriptive compounds first. Examples:
   - de Eichbach, Steinfeld, Mühlhausen, Brückenau;
   - fr Pont-sur-X, Roche-, -sur-Mer;
   - usa Oak Ridge, Stony Brook, Mill Creek;
   - nl Eikendal;
   - sv / nb Ekby;
   - and the others likewise.
6. **Name lab:** a preset "descriptive (§60)" next to the earlier ones, so the user can compare.
7. **Tests:**
   - at least about 80 % of town names contain a readable site word that matches the town's tags or cues;
   - opaque stems at most 1 per 16;
   - quiet names at most about 10 %;
   - no repeats (existing gates);
   - the 0341 and 1729 site replays print samples.

Addition from the user during the work: "descriptive names and multi word names that help make it clear its
context-aware" (Oak Hill, Stony Brook, Mill Creek, Arun Bridge, High Moor; 40-60 % multi-word on en / usa maps, never
more than 3 words, the word budget and no-repeat rules kept).

Results (2026-10-15, offline; details PLAN.md 6.3 "Literal, context-aware names first"):
- DONE items 1-5: the s60 rules (`ot_placename.RULES`, default; `o.rules = "s53"` gives the §53 names exactly): opaque
  stems (+u morphemes, +p personal names) `OPAQUE_PEN` 2.0 and at most 1 per 16 towns; flavor parts (+n: Aber-,
  Llan-, Kirk-, -by, -thwaite, -beck; de -reuth / -büttel, nl -drecht, sv -tuna ...) only on 1-3 planned flavor towns
  per 16 (a river or a coast / edge dialect area first; the dry US map's Spanish group counts as flavor); quiet names
  10 % from readable stems (New, Middle, Kings, Nor-, Sut-); a pair naming no feature 0.5 lower on the other towns; the
  cue-bearing shapes (whole x3, qualifier x2, frame x2.5) up to about a third, a frame on the town's named feature
  first, a whole name that drops the town's river lower; new readable stems and multi-word generics in en
  (`_Hill _Heath _Moor _Green _Common _End _Cross _Bridge _Wood _Dale _Vale _Water _Brook _Mill _Cliff _Fen _Marsh
  _Edge _Fell _Head _Ford _Sands`, Two Waters) and usa (Mill, Stony, Middle, Ash, -kill, _Run; no "Lake Shady"); en /
  usa multi-word share `SEP60` / `WORDS60` / `SEP_BONUS`. Every generator language runs the same rules. Budget,
  climate fit, survey agreement, character forms and created-town naming unchanged.
- DONE created towns: no district on an opaque parent stem or on the first word of a multi-word parent ("Middle Fork"
  -> "Middle Fork Heights", not "Middle Heights"); en district / Works forms in plain words (Riverside, Meadows, Falls,
  Watersmeet, Landing for Ings, Holme, Clough, Force, Staithes, Delph).
- DONE item 6, name lab: a "Rules" select, "descriptive (§60)" / "review (§53)", in the site lab and on the old page's
  Whole map card; `golden53` runs; check_port.mjs 7584 / 7584; gen.js is generated from gen.ts (`names/gen_js.mjs`);
  data.json's map is the 0341 run.
- DONE item 7, tests: test_names60.lua (22). Full mode, 16-24 towns: en site word 84-87 % per climate, multi-word
  42-46 %, quiet 10 %, opaque 0 per 16, flavor 1.3 per 16; usa site word 85-89 % (dry 78 %), multi-word 57-62 %,
  quiet 9 %, opaque 0; de / fr / it / es / pt / nl / sv / nb / ja site words 86-91 %, quiet 10-15 %, opaque 0.
- Samples (seed 1, start 1950):
  - 0341 sites, en, game (s53): Brynchurch Cove, Mytham, Dart Head, Lower Aberarun, Shaw, Padfield, Oakhaven, Ashminster
    Garden City, Hornness, Abercoed, Kelington, Edton, Winmere, Trefach, Wemmead, Milton-under-Edge. After (s60):
    Shinglewater Cove, Bridgeworth, Two Waters, Lower Glavenmouth, Upton-in-the-Forest, Newfield, Oakhaven, Ashminster
    Garden City, Penness, Birkby, Wood Vale, Little Daleshaw, Daleshaw, Holt, Monkmead, Twinley-on-Hodder (site word
    12 / 16, multi-word 8, opaque 0, flavor 2, quiet 2; the replay's s53: 8 / 16, 4, 7, 2, 6). Districts Bridge Hill,
    Glavenmouth Gardens, New Bridge, Ashminster Gate, Birkby Moor, Daleshaw Park; Works Lower Glavenmouth Carriage
    Works, Smithside, Birkby Wharf.
  - 1729 sites, usa, before (s53): Swanport, Twinmont, Glen Pine, Lower Turkeyboro, Holliswood, Coalfield, Hickory
    Harbor, Grand Woods, Oak Point, Shady Forks, Russell Prairie, Lyman Flats, Garrisondale, Ellis Flats, Morganville,
    Three Rivers (12 / 16, multi 10, opaque 6). After: Swan Harbor, Middle Fork, Port Pine, Lower Turkeyboro, Lake Ash,
    Hemlockfield, Hickory Cove, Ashwood, Oak Point, Shady Ferry, Deerville, Fair Flats, Laureldale, Cedarmont,
    Coalville, Otter Forks (14 / 16, multi 10, opaque 0). Districts Middle Fork Heights, Turkeyboro Estates,
    Hemlockfield Acres, Ashwood Village, Shady Ferry Gardens, Fair Flats Meadows; Works Ironton, Furnace Junction, Shady
    Ferry Landing.
  - de valley map after: Krummstadt, Wiesesiel, Klosterhausen, Weidenbruch, Kreuzfelde, Brückmünden, Angertal,
    Oberklosterhausen, Eichwalde, Kesselfurt, Fährtal an der Alb, Wiesenwald, Nordfeld, Hoheneichwalde, Holzfenn,
    Stegmünde (13 / 16, opaque 0; before 10 / 16, opaque 7: Wolfratsleben, Hammelfeld, Gundmünden ...).
  - fr valley map after: Tremblecourt, Bas-Ornelieu, Saint-Loup, Saulechamp-le-Marais, Landebourg, Gué-du-Confluent, Le
    Val, Hautemont, Chesnville-en-Forêt, Pont-des-Champs, Montroche-sur-Dore, Val-du-Bois, Vertechamps, Bonnechamp,
    Aulnemesnil, Port-de-la-Mer (13 / 16, multi 9, opaque 0; before 10 / 16, opaque 2: Rouvy, Juilly).
- Not done / notes: German, Dutch and Nordic names stay mostly one word (their natural compounds; multi-word 6-14 %);
  it / es / pt / ja have no flavor parts marked (no dialect groups); the site lab's single-site runs simulate the caps
  (one flavor town in 8), only the map modes run the plan; some forms still read odd (Seaness-on-Thornwater,
  Upton-in-the-Forest on a common base, Lake Ash) and want the in-game look.


## 61. Evocative names, every character town's kind, the industry as a cue (2026-10-15; done offline 2026-10-15; run `2026-10-15_0429_sqot-sqrl`; details PLAN.md 6.3 "Evocative names, every character town's kind, the industry as a cue"; in game: TESTING.md "Combined test iteration" step 10)
The user, after run `2026-10-15_0429_sqot-sqrl` (seed `a`, europe, 1950, s60: Seachurch Cove, Bridgeham-under-Dun, Two
Waters, Lower Arunmouth, Shaw, Wheatden, Oakhaven, Ashminster Garden City, Hornness, Abercoed, Upper Doveley, Monkton,
Meregrove-on-Brantmere, New Wood, Norfield, Doveley):
> "i like two waters name a lot. anything that is kind of obviously part of the environment is neat"
> "if character names don't already factor into city name that would be cool, too"
> "also, city name could potentially take into account what type of industry they are. fishing town, fuel, brickets,
> etc. but that would just be one additional environmental cues"

Asked:
1. **Evocative environment names** like Two Waters: whole or multi-word names that plainly describe the site, each on
   a real reading (Three Rivers / Watersmeet, Twin Lakes / Broadwater, Seven Oaks / Ashgrove, Long Meadow / Wide Fen,
   Windy Ridge / Fell Foot / Dale Head, Sandy Point / Rocky Bay / Cliff End, Bridgend / Ford End; per language), about
   15-25 % of the towns, none repeated, the s60 quotas coherent.
2. **Every character town carries its kind:** the strong kinds plus deep forest, the secluded character towns and the
   coastal hugger (the last three passed from the driver).
3. **The industry as a cue:** a town with an industry within ~1.5 km may take a name from its type, at most ~1-2 per 16
   towns, only near that industry, never repeated.
4. **Name lab:** port everything, the check green.

Results (2026-10-15, offline; the rules "s61", default; `o.rules = "s60"` / `"s53"` give the earlier names exactly):
- DONE item 1: per language `affix61` lines; evocative names `+g` (17-29 per language) with gates `?tag[:min]` on the
  town's reading before rarity (`?lakes2`: two lakes near, the survey's new `waterNear().lakes`); the plan's step 2b
  (after the whole names and the twins) hands about `EVOC_SHARE` 0.21 of the towns (at most 0.25), each name once,
  never to the town that spends its river first; multi-word ones take a `separate` name off the count; their roots
  stay in the word budget. "Ford End" is out: "ford" is a blocked brand word (en uses Bridgend / Stepping Stones /
  Ferryside). Offline 15-20 % of the towns per language on maps with two character towns.
- DONE item 2: `charForms61` in every language for all 11 kinds (hilltop, harbour, cove, street, company, garden,
  island, market, forest, secluded, coastal); `CH.NAME_KIND.deep_forest = "forest"`, `CH.NAME_SECLUDED`,
  `CH.NAME_COASTAL`; the driver's `namesKinds` passes them (deep forest predicted at naming: `FO.deepSite` + the
  draw, at most `DEEP_MAX`; the plan's pick then follows the name, `s.nameDeep`); a character town never falls back to
  a plain name (two-word romance bases allowed, one idea more, the word budget waived last). 100 % carry in every
  language offline.
- DONE item 3: `+i !family` forms for fish, oil, clay, coal (and ore mines), stone, timber, farm, iron in every
  language; `namesIndustryCue` (nearest cue industry within `IND_R` 1500 m, `OFF.indType`); plan step 0b: `IND_SHARE`
  0.09, at most 2 per 16, one per family, the nearest / most telling first. Offline 1.4-1.6 per 16. The quiet share
  now counts only the towns left plain (else pt reached 15 %); usa keeps `WORDS60` 1.7 (multi-word stays under 60 %).
- DONE item 4: gen.ts ports it all; Rules "evocative (§61)"; `golden60`; check_port.mjs 11376 / 11376, check_port.js
  3792 / 3792.
- Logs: NAME `evoc=<gate reading>` `ind=<family>:<m>` `char=<kind>` (the survey's `cue=` unchanged); NAMES shapes
  `evoc= charCue=<carry>/<kinds> indCue=`; FOREST `why=...,named` / `why=names:...`.
- Samples (replays, seed 1, 1950; the industries at their run's towns, 900 m):
  - 0429 sites, en, in game (s60): Seachurch Cove, Bridgeham-under-Dun, Two Waters, Lower Arunmouth, Shaw, Wheatden,
    Oakhaven, Ashminster Garden City, Hornness, Abercoed, Upper Doveley, Monkton, Meregrove-on-Brantmere, New Wood,
    Norfield, Doveley. Replay s60: Shinglewater Cove, Bridgeworth, Two Waters, Lower Glavenmouth, Upton-in-the-Forest,
    Newfield, Oakhaven, Ashminster Garden City, Penness, Twinthorpe, Wood Vale, Little Daleshaw, Daleshaw, Holt,
    Monkmead, Otterley-on-Hodder. After (s61): Fellwater Cove, Two Waters, Far Cuckmeredale (secluded), Lower
    Glavenmouth, Little Wheatden, Wheatden, Seven Oaks, Ashminster Garden City, Seaholt Sands (coastal), Watersmeet,
    Ashgrove, Newfield, Oil Springs (oil), Shaw, Dalewood, Hoddermouth-in-the-Forest (deep forest): evoc 3, charCue
    5/5, indCue 1, multi 10, quiet 1. Districts Two Waters Heights, Glavenmouth Vale, Wheatden Gardens, Ashminster
    Gate, Watersmeet Park, New End; Works Lower Glavenmouth Carriage Works, Cinderside, Watersmeet Smokehouses.
  - 1729 sites, usa, s60: Pelicanwood Cove, Middle Fork, Pinefield, Port Turkey, Lake Ash, Hemlockton, Hickory Harbor,
    Ashville Garden City, Oak Point, Twinmont, Deerburg, Fair Flats, Swandale, Shady Grove, Coalville, Lower Otter
    Landing. After: Pelican Hills Cove, Mount Signal, Far Pinefield, Port Turkey, Lake Willow, Hemlockton, Bayside,
    Ashwood Garden City, Mirror Grove Beach, Three Forks, Ash Junction, Cedar Oaks, Swandale Wells (oil), Laurel Flats,
    Coalville, Ottermont Woods: evoc 2, charCue 5/5, indCue 1, multi 13, quiet 1. Districts Mount Signal Heights, Port
    Turkey Gardens, Hemlockton Village, East Ashwood, Three Forks Park, Cedar Oaks Estates; Works Port Turkey Locomotive
    Works, Prentice Furnace, Forgeport.
- Not done / notes: the deep forest prediction needs the town's forest read done at naming (else the old draw, and the
  name may lack the cue); the site lab's single-site runs only sample the evocative shape (every 5th town); found on
  the way: `Driver:charIndustry` reads `it.x` / `it.y` of `E.industries()` entries, which are `{ x, y }` arrays, so
  no town has been a company town in the last 8 runs (`noIndustry` everywhere); not fixed here (it changes the
  character picks of new maps).

## 62. Landscape pull: big-scale cues steer the town's overall growth; company towns readable again (2026-10-15; done offline 2026-10-15; user run of 2026-10-15 (US names, European build style, 1900; HISTORY.md, log lost); details PLAN.md 6.2 "Landscape pull"; in game: TESTING.md "Combined test iteration" step 11)
The user, watching that run:
> "i wonder if we should have more weight to build in a general direction away from forests. but on a larger level ...
> imagine the forests pushing growth away, and towns wanting to fill in where the green lines are going. we can keep
> all our existing logic, but jsut try to weight overall high level growth using bigger geographical cues if we aren't
> already doing this"
> "yes we need bigger scale influences. water, mountains, foreset, prairies, canyon, etc"

The screenshots: Lower Deer Forks, Twin Rivers, Buffalo Prairie, Oakport and Lake Stone pushed streets into or along
woods on one side while wide open flat land on the other stayed empty. Before: the town's overall direction
(ot_select `preference`) was seeded sectors + the coast lean + away from industry; the forest acted per piece only (hug
/ deep mode), and nothing read hills, lakes, rivers or open land at the town's scale.

Asked: a per-town smooth angular field from big-scale cues (forest, open land / prairie, steep ground, water, valleys)
blended into the preference as one more lean, the hotspot / lobe headings biased toward favoured land, scaled by
asymmetry, capped so the seeded variety stays, deterministic, recomputed with the readings, shaped / character towns
damped, a compact log. Also (user-approved): fix §61's `Driver:charIndustry` find.

Results (2026-10-15, offline):
- DONE `ot_land` (new, pure): 16 sectors from the tree grid (mean cover of the ring r0..1450 m, r0 beyond the town's
  extent), the wide survey's rays (`ot_terrain.wide` keeps its 64 points now; grade per ray, uphill full / downhill
  0.6; wet points; off-map points as wet) and the disc's water (`stats.water`: the river / shore the 500 m ray steps
  miss; its bank / shore axis pulls). F = 1.0 open - 0.8 forest - 0.9 steep + 0.6 shore, smoothed, centred, lean in
  [-1, 1], k = 0.35 x asymmetry (range 0.2-1.0). Valleys / canyons come out of the steep cue (walls rise on two sides:
  the floor axis wins both ways), hillsides favour the contour, water pulls along the shore and never across.
- DONE ot_select: `seededPreference` (the old one), `preference` = blend by weight, `reach` = 1 + ampSeed x seeded +
  ampLand x lean (shaped: SECTOR_DAMP / SHAPE_F 0.5), floor 0.3; the sum capped at `TOTAL_MAX` 0.55 (both scaled):
  EU organic keeps 0.275 seeded + 0.275 land at full asymmetry. No field: exactly the old cost.
- DONE style factors: clear-mode towns forest x 0.5, deep forest towns x 0.3, character towns k x 0.5 (hilltop: no
  steep cue; waterfront / clifftop / harbour cove / island town: no water cue), coast lean present: water x 0.5.
- DONE driver: `Driver:landRefresh` each snapshot after the forest mode (cached raw reading per grid / survey / stats /
  r0 step: a forest re-read or a grown town recomputes; a changed field redoes the cached preference); lobe headings
  re-ordered favoured-first (`LAND.orderDirs`, from k 0.08); `D.markOffMap` on the wide survey. Nothing saved: old
  saves load, a town without readings plans as before.
- DONE logs: LAND (always on, once per town and change) `town= name= cues=open:W,forest:E k=0.35 kRaw= A= to=180
  away=0 r0= forest=true why=clear shape= lobes=`; PLAN `land=open:W,forest:E/k0.35/to180`.
- DONE `Driver:charIndustry` reads `it[1] or it.x` / `it[2] or it.y` (ot_engine.industries gives `{ x, y, file, e }`).
  Replay over the archived CHECK `ind=` lines (23 map loads, 2026-10-13..15): 0 company towns would have been picked
  anyway. The starting towns' nearest industries sit 1236-1577 m out (seed `a`: none within 1.5 km); the kind needs
  0.4, i.e. a heavy works within 1275 m (medium 1075 m) and meanSlope <= 0.05; one town scored 0.40 (81939, 1277 m) and
  was too steep. docs/findings/towns.md "New maps place industries 1.2 km or more ...".
- Tests: test_land.lua (new, 14): forest on one side -> the lean peaks toward the open side at k 0.35; flat / forest
  all round -> k 0; a rising plane -> contour over uphill and downhill; a valley -> along the floor both ways; a coast
  -> along the shore, never across; a river 120 m south -> the banks over the far side; off-map -> push; prairie
  (forest north, mountain east) -> peak south-west; the style factors; no field = the old preference exactly; the cap
  (ampSeed >= 0.7 amp, reach ratio <= 3.44, the favoured heading still varies by town: 3+ of 12 bins over 40 towns);
  growth: 8 increments of EU organic from a round core with woods east: west share of the new street length 0.60 ->
  0.74 (the east still grows); lobe order; the grid read's cap; landRefresh (field, one LAND line per change, the
  forest re-read, off); an old town state without readings; charIndustry with `{ x, y }` entries.
- Not done / open:
  - No replay of the lean on real maps: the archived logs have no heightmap or tree grid per direction (FOREST gives
    the share only). The first run's LAND lines give the per-town directions; check them against the user's arrows.
  - Calibration in game: K_MAX 0.35, TOTAL_MAX 0.55 and the asymmetry range (A0 0.2, A1 1.0) are offline guesses;
    if towns read as one-sided wedges, lower K_MAX first; if the open land still stays empty, raise it (to 0.45) or
    A0 down.
  - Company towns: the kind's distance scale doesn't fit the game's industry placement (score 1.25 - d / 1500). If the
    user wants them, a separate change: e.g. full score within 1000 m, 0.4 at about 1700 m (`CH.COMPANY_R` 2000).
  - The lean acts on the cost order of the master plan's pieces (and the hotspots / lobes); the master plan itself
    still lays spokes all round. A town boxed in by woods on three sides still grows into them once the open side is
    used (by design: a lean, not a wall; the hug mode's per-piece logic does the rest).

## 63. Landscape-aware skeleton: the locked arms keep off the woods and reach into open land (2026-10-15; done offline 2026-10-15; run `2026-10-15_0539_sqot` (seed `a`, EU names, EU_ORGANIC, 1900, Quick 40 years, calendar not moved); details PLAN.md 6.2 "Landscape-aware skeleton"; in game: TESTING.md "Combined test iteration" step 12)
The user, after the run:
> "it still seems like the towns take over forest too quickly. the initial locked streets play an important part of
> the early growth, and they aren't drawn aggressively enough in some situations. remember that roads built houses on
> them, which then take over the forest. so ideally we take that into account when considering spacing"

Compared with the same map before §62 (`2026-10-14_1927_sqot`, 1900): hug 11/16 vs 8/16, mean forestCut per plan
0.20 vs 0.23, buildings at year 40 10661 vs 13192: §62 only reordered the planned pieces (every town got a LAND line,
k 0.09-0.35), while a shaped town's arms (the cheapest corridors, the arm fronts, locked "arm" streets) still went
out at their seeded headings, e.g. Far Ashworth's W arm into `forest:W`.

Asked: the initial locked skeleton landscape-aware (arm headings / lengths from the §62 field and the tree grid; a
locked street's centreline at least lot depth + a margin off dense forest, both sides' lots counted, unless deep or
no alternative, logged), drawn further into open land, seeded variety and shape intents kept, the same for satellite
sites / links where cheap, a light edge clearance for clear-mode towns' ordinary growth, the LAND cue fix, a log of
the skeleton per town, tests, docs.

Results (2026-10-15, offline):
- DONE `ot_skeleton` (new, pure): per arm a survey from 0.8 x the houses' extent 900 m out every 25 m; clearance to
  dense forest (cover >= 0.5) along the normal both sides, ahead and on the forward diagonals, to 100 m; the open run
  ends under `CLEAR_M` 65 m (lot depth 36-40 m + ~25-30 m for the smoothed 50 m cells). Acts: keep / long, bend (an
  unused spoke within 75 deg on organic plans, 20 / 40 / 60 deg turns elsewhere, linear / ridge <= 65 deg; must score
  150 m more: open run + 150 m x the §62 lean), short (`shape.armMax` at the end of the open run), drop (run < 200 m,
  another arm open, min arms 1 / 1 / 2 / 3 for linear / ridge / cross / fingers), boxed (no alternative: kept as is,
  `why=noAlternative`). Open arms: `shape.armK` up to 1.6 (1 + 0.4 x the lean term + 0.15 per cut arm) on the reach
  (SH.distance), the arm fronts' reach and the fill rule's lead. Deep towns exempt; character towns no bend / drop
  (`intent`); site arms and strict grids no bend; metropolis variants and dev jobs untouched.
- DONE ot_shape: `armMax` (past it the distance along runs at the core's rate; inArm / armAt: no arm, so no "arm"
  lock), `armK`, `shape.site` / `shape.dev`; ot_core rebuilds the master plan when the arms change (`skelKey`).
- DONE saved: the frame's `sk` text (ot_saved, at most 160 chars), decided before the first build (again on a new
  tree grid until the frame goes out), decoded on reload; a frame without it (older saves) keeps its arms exactly.
- DONE ot_select: hotspots / lobes of unshaped towns move off the woods (turns 20-60 deg, radius x 0.75 / 0.55;
  `SK.movePoint`); clear-mode towns' wooded pieces x (1 + 0.6 x hug odds x corridor pen) (`FO.clearFactor`).
- DONE ot_satellite: sites by the woods score + 1.2 x wooded surroundings, + 0.5 x the link's cover (deep: none).
- DONE ot_land cue fix: cue names from each cue's own top run of sectors (`LAND.peakHeading`), open land only among
  sectors with at most mean forest (Seachurch Cove's `open:N,forest:N`: the old resultant of the open sectors fell
  between two forest lobes). `to=` / `away=` and the lean itself unchanged.
- DONE log: SKEL (always on, once per town and change) `town= name= shape= src=new|saved|old|noGrid mode= arms=<deg>:
  <act>:<run>:<clear>:k<x>[:from<deg>][:max<m>]/... dropped=<deg>:<why>:<run>/... minClear= boxed= why= hot=<moved>/<n>
  clearM=65 r0=`.
- Tests: test_skeleton.lua (new, 15): survey / clearance; woods on one side (the cross's east arm onto an open spoke,
  every kept arm >= 65 m clear, open arms k > 1); two sides (linear: the open end long, the wooded end shortened /
  turned); boxed in (all kept, `noAlternative`); deep / character / site / strict grid; SH cap and reach; the saved
  text and frames (old frames: none); growth (EU organic linear town, woods from x 330 m, 10 increments: street metres
  with lots in the woods 1693 -> 95 of ~5.3 km; clear mode alone 1301; hug 68 -> 30); driver (new / saved / old,
  re-decided on a new grid before the frame, kept after; dev / metro / off untouched); hotspots; the clear-mode cost;
  satellites; the LAND cue fix; hang guards.
- Not done / open:
  - No offline replay of seed `a`: the archived logs carry the forest share and LAND cues, not the per-direction tree
    grid. The next run's SKEL lines give each town's arms; check them against the screenshots.
  - Calibration in game: CLEAR_M 65 m, MIN_ARM_M 200 m, BEND_GAIN_M 150 m, K_MAX 1.6, CLEAR_COST_K 0.6. If arms still
    end up beside woods, raise CLEAR_M (80); if too many towns read one-sided, raise BEND_GAIN_M or MIN_ARM_M down.
  - Compact / lens / fan / twin / shore towns have no arms to steer (only hotspots / the cost): twin's second core and
    the shore strip are not checked against the woods.
  - The game's own development still fills the core's unlocked streets wherever they are; hug towns' facing streets stay
    locked as before.

## 64. Every satellite a named town: Works and districts 2-4 per 16 towns, the streets-only seeds retired, a fixed draw (2026-10-15; done offline 2026-10-15; run `2026-10-15_0539_sqot` (seed `a`, EU names, EU_ORGANIC, 1900, Quick 40 years); details PLAN.md 6.2 "Named offshoot towns instead of street satellites"; in game: TESTING.md "Combined test iteration" step 13)
The user, after the run: no satellite towns, meaning "the completely different cities that we had": the separately
named Works ("Hornness Foundry", "Haslemere Works") and district towns ("Aberdart Grange"), real game towns, linked.
Agreed plan: every satellite a real named town, the streets-only satellite retired (0539's were bare X / T crossings,
e.g. 1.2 km NE of Two Waters at -873:917, founded year 20, one dose, never filled), ot_satpace's staggered timing
kept; about 2-4 per 16 towns, never zero from a failed seeded roll; find why street satellites crowd out districts;
the §62 / §63 landscape rules for the sites; houses per offshoot counted in the log.

Root cause of "rare" and of the crowding out:
- 0539's five foundings (simulated years 12, 20, 24, 32, 40) were all streets-only seeds. `satelliteDecide` runs first
  in every job and `paceGate` caches its verdict on the job, so in a satellite-eligible town the Works / district
  decision of the same job reused the seed's "wait" / "deferred" without a line of its own: Two Waters, Merehythe,
  Watersmeet, Holtbottom and Norfield logged no DISTRICT decision at all (Watersmeet / Holtbottom / Norfield were
  district-eligible). A founded seed also raised the town's readiness (k = 1: Two Waters' Works waited at
  `target=772`, Merehythe's district at 603), and took the slot. In run 1927 (no pacing yet) Merehythe's town 60257
  founded Aberdart Grange.
- The draw itself was broken. `ot_rng.hash` is affine mod 2^31 - 1 in its inputs, so `rng.unit(seed, a)` and
  `rng.unit(seed, b)` for two labels of the same length are the same draw shifted by a constant mod 1: `district` =
  `leadLane` + 0.649, so every town with a seeded lane ahead (u < 0.3) had u_district in [0.649, 0.949): always rare
  at CHANCE 0.6 (Seven Oaks and Wheatden in 0539; Far Ashworth is a character town); `works` = `shape` + 0.430 =
  `metro` + 0.708 (Works only for one band of shape draws); `satellite` = `siteStyle` / `shoreForm` shifted; and seed
  vs seed + 2 correlate -0.31. Marginal shares were right (0.354 / 0.597 over random seeds), so it showed as specific
  towns always rare. A nil seed falls back to 1 (works 0.55 rare, district 0.463 seeded), but the driver always passes
  `style.seed` (rng.seed(id, x, y)), never nil. The seeds are a function of the town id and position, so the same map
  repeats the same verdicts in every run on seed `a` (0341 / 0429 / 2237 / 0539).

Results (2026-10-15, offline):
- DONE `rng.draw` (ot_rng): M.hash, then three rounds of x -> (x + c)^5 mod p (a bijection). Used for WK / DT
  eligible, SP.key and SP.need only; `rng.unit` untouched, so no other seeded outcome changes. 20000 seeds: works
  0.353, districts 0.602, districts among lane-ahead towns 0.600 (was 0); chi-square (10 x 10) of works / district,
  district / leadLane, works / shape, seed / seed + 2, district / satellite all under the 0.1 % line.
- DONE streets-only seeds retired (`D.STREET_SAT` false): `SATELLITE on=false why=retired` (debug, once per town), no
  "satellite" offshoot turn; a save's satellite (frame `sx sy`) is restored and grows as before; the dev tools'
  forced crossroads hamlet still seeds one. Nothing removed from the save format.
- DONE quotas (ot_driver): Works + districts at most 4 per 16 towns (`OFF_PER16` {2, 4}, rounded, at least 1; n = the
  map's own towns, the mod's offshoots left out), the kinds' own quotas on top. Fallback while under 2: a "rare" town
  of 400+ (`OFF_QUOTA_BUILDINGS`, offshoot size units) founds the kind the map has fewer of (a district first;
  `why=quota`); smaller ones keep their tries (`quotaWait=true`) and the offshoot turn stays due for them.
- DONE stagger: SP.SPACE_B 520 -> 850 (fewer foundings to space).
- DONE sites: `WK.landScore` in both ring pickers: + 1.2 x wooded surroundings (ot_skeleton.pointClear, 185 m),
  + 0.5 x the link's cover, - 0.35 x the §62 lean at the heading. District kinds "cross" (country crossroads within
  250 m, the lane end's names) and "open" (no feature; bonus 0.45; `DT.OPEN`), so plain land founds districts where
  the satellites used to go. Character / deep towns, gap / neighbour rules, ot_link, ot_offname unchanged.
- DONE logs: create lines `land= why= simYear=`; the not-eligible lines `quota= quotaWait=`; OFFSHOOTS (always on, per
  Simulate round and every 300 real s): each offshoot town's buildings, its parent and founding year.
- Tests: test_offshoots.lua (new, 9): the old shift, the draw, the quota and fallback, a 300-map 40-year model (every
  map 2-4: 2: 25, 3: 25, 4: 250; 129 of 1125 via the quota; first at simulated year 4-16, median 8; last 12-40, median
  28; one per round), the landscape terms and the "cross" / "open" kinds, the driver glue, an old save's satellite,
  OFFSHOOTS, the loop caps. test_satpace's model bounds 6-10 -> 3-8 (SPACE_B); test_district's flat-land case now "open".
- Docs fixed in the same change: PLAN.md 3.1 (satellite village per map), the module table, TESTING.md "Staggered
  satellites" (6-10 expected), mod description (satellite villages, the lane toward the satellite, district sites).
- Not done / open:
  - Offshoot towns grow by the game's own demand (transport): a district fills its first ~60-80 buildings and then
    grows slowly (Aberdart Grange 70 -> 78 over run 1927). If OFFSHOOTS shows them flat, a later phase could dose them
    (the mod's FILL / a size command per pod growth) - not done here.
  - In game the towns' seeds and sizes differ from the model; seed `a` may hit the max (4) early or rely on the
    quota. Calibration: OFF_PER16, OFF_QUOTA_BUILDINGS 400, SPACE_B 850, LEAN_W 0.35, WOOD_W 1.2, the "open" bonus 0.45.
  - Other same-length label pairs of `rng.unit` stay one shifted draw (e.g. `forestDeep` / `forestMode` / `entryTrees`,
    `siteStyle` / `satellite` / `shoreForm`); they were left as they are (changing them would move many other seeded
    outcomes).

## 65. Lock every mod-built street: the game branches only off the town's own streets; the stall guard (2026-10-15; done offline 2026-10-15; run `2026-10-15_0629_sqot` (seed `a`, EU names, EU_ORGANIC, 1900, Quick 40 years); details PLAN.md 6.2 "Lock every mod-built street, the stall guard"; in game: TESTING.md "Combined test iteration" step 14)
In 0629 the 16 towns went from ~706 to ~3880 street edges and CHECK `ownEdges` summed to ~1100, so about 2/3 of the
new streets were the game's own. They ignore the forest holds, open land and shapes, which is why the forest loss did
not drop. `ownEdges` checked: ot_assess.lots counts a lot edge as own when it is `roadDevelopmentLocked` or built by
the mod this session (s.own), so in a one-session run it is the mod's live streets (a mod street the game split loses
its id: a small undercount). The user chose the middle option: keep the town's starting streets (and the player's)
unlocked, lock every street the mod builds, and make the mod supply enough frontage.
- DONE lock: `D.LOCK_DEFAULT = "mod"` (ot_driver): every mod street locked, every proposal kind (they all go through
  `send` -> `buildInfo`; ring quarters, lanes, links, bridges, frames, offshoot streets, the lane ahead's far end too).
  "legacy" keeps the shape lock (LOCK_SHAPE); a job's `lock` and the dev hook `ot_hooks.lockDefault` override.
  Nothing locked by the mod relied on later game branching except the lane ahead's far end (now locked in "mod"
  towns); the wedge frames look for the game's unlocked tips and still find them; ring / junction builds never
  rebuild existing streets, so locking new edges changes no junction.
- DONE saves: frame `lm = 1` ("mod") and `e0` (the core's edge count) written with the town's first frame; a frame
  without `lm` (old saves) stays legacy, a town first built after the load gets the default. Additive only.
- DONE supply: LOCK_LEAD_K 1.5 on a young "mod" town's lead floor (phased out by maturity); the stall guard
  (ot_assess.stall + Driver:stallGuard): under 0.85 of target, buildings flat (< 3 %), open frontage under 2 x the
  need, 3 checks in a row -> fire, level 1-3 (bigger increment + own empty budget; + wider envelope; + forest hold a
  step looser, last), at most 12 fires per town and session, never for held / over-target towns.
- DONE logs: CHECK `lockMode modEdges gameEdges coreEdges gameShare stallStreak stallFires`, PLAN `stall forestStep`,
  BUILT `lockMode`, STALL lines, STREETS (map-wide, every 600 real s), INIT `lock= lockLegacy=`.
- DONE dev A/B: showcase probe row + "EU organic (old lock)", "Shape: linear (old lock)"; LOCK lines with `lockUsed
  edges gameEdges gameShare cap capRatio`. Variant (c), rebuild and lock the core, skipped: it would rebuild live
  streets and junctions of the showcase towns.
- Tests: test_driver (8 new: default lock and frame, old saves, every kind, the stall guard pure and in the driver,
  street split and STREETS, the lead factor); test_demand (lane ahead: all locked in "mod" towns; the maturity model
  under the legacy lock, as measured); dev test_layout / test_showcase (the twins, the LOCK fields).
- Open: the game may still build a large share off its own (unlocked) new streets; the stall thresholds are untested
  in game; the game widening / unlocking a locked street was never seen.

## 66. Supply-driven district weighting: "Town growth: By deliveries", on by default (2026-10-15; done offline 2026-10-15; Phase 0 measured in session `2026-10-15_0759_rci-sqrl`; details PLAN.md 6.2 "Supply-driven district weighting"; in game: TESTING.md "Combined test iteration" step 15)

The user's brief (2026-10-15), kept close to verbatim:

Add a mod.json setting to square_organic_towns, "Town growth" with the values By deliveries / Game default, default
By deliveries. With it on, each town's residential, commercial and industrial (R/C/I) mix follows what the player
delivers, and towns can become clearly lopsided: a mill town that is 70% industrial, a market town that is 60%
commercial. Organic Towns then shows that mix in its streets. Follow plans/README.md, CLAUDE.md and the memories (one
subagent per phase; the main session orchestrates).

Background (read first): docs/findings/towns.md, sections "Level curve", "Growth factor", "Target and trigger",
"District split", "Apply", plus "makeTownDevelopAtCmd resets the town's initial capacities". The base game already grows
towns without a cap and splits each increase by line use and cargo supply. It then evens the split out: each district
keeps a minimum share (townGrowthMinDistrictFraction), and its maximum share shrinks toward 0.5 once it passes 40% of
the town. That evening-out is what we work around. The lever is NTG's: raise a district's initialLandUseCapacities with
makeTownSetInitialLandUseCapacitiesCmd; the target is Σ initial × sizeFactors, and the game never lowers sizes a mod
sets. Organic Towns already writes these values: ot_engine.lua:429 (starting size) and the FILL restore around
ot_driver.lua:160 / ot_engine.lua:1112 (line numbers as of the brief; re-find them). The weighting must go through that
same path, never a second writer, and the restore must keep the weighting's values instead of overwriting them. (§58:
the FILL restore also refills the per-level weights; keep both consistent.)

**Phase 0: measure (before any code).** DONE 2026-10-15: session `2026-10-15_0759_rci-sqrl` (a played base-game save,
"sub-arctic", US towns, Organic Towns off), 15 towns of 417-3964 persons: residential 25-47 %, commercial 20-50 %,
industrial 13-41 %, no district above 50 % (findings towns.md "District split" -> "Measured spread"). Base towns vary but
never turn clearly lopsided: the full weighting was built, not only the visual tie-in. The brief as given: Find out how lopsided base-game towns get. Check archived sessions first
(`make logs-grep`). If none has per-town R/C/I data from a played save, give the user this console one-liner to run on
a mid- or late-game save without Organic Towns, then read its [RCI] lines from the live log:

    for t,c in pairs(api.engine.system.townBuildingSystem.getTown2personCapacitiesMap()) do local n=api.engine.getComponent(t,api.type.ComponentType.NAME); print("[RCI]", n and n.name, c[1], c[2], c[3]) end

Record the spread (the share of each district per town) in docs/findings/towns.md with the session name. If base-game
towns already range widely, say so and narrow the phase to the visual tie-in.

**Phase 1: plan** (PLAN.md, a new 6.x section):
- Inputs per town: residential = passenger line use and reachability; commercial and industrial = supply of their
  cargo, read through the base town_util / town_util_parallel helpers (getCargoSupplyDemandsLandUse…), never by
  recomputing.
- The formula: how supply moves the starting capacities. Gradual: smoothed over game months, a cap per step, a floor
  per district so no district goes to 0, and an overall ceiling so total growth stays close to the base game (we change
  the mix, not the speed).
- Starting sizes: less random variation for new towns (NTG did this), within the existing "Starting town size"
  setting.
- Visual tie-in: an industrial-heavy town leans toward Works districts and industrial streets (ot_works, §64 offshoots);
  a commercial-heavy town gets a denser core through the per-level building weights
  (makeTownCustomDistributionWeightsCmd) already in the per-style weights; a residential-heavy town gets suburbs and
  ribbon growth along its main roads.
- Existing saves: follows "Act on" (Off: nothing; New towns only: only towns the mod tracks). In an old save, adjust
  from the town's current mix slowly, never with a jump. Removing the mod leaves the sizes where they are (the game
  never lowers them): note this in the description.
- Every loop over towns gets a hard cap and a per-tick budget (CLAUDE.md "Mod scripts run on the game thread").

**Phase 2: build.** A new module (e.g. ot_rci.lua) with pure functions for the formula, plus the wiring in ot_driver.
Log tokens such as `RCI town=… r/c/i=… supply=… caps=a,b,c->x,y,z` so the dev tools and make logs-grep can follow it.
Tests in tests/square_organic_towns/: the formula (floors, caps, smoothing, no NaN, zero supply), a lopsided town
converging without overshoot, Act on Off doing nothing, the restore keeping the weighted values, and the per-tick cap.
A full-mode sweep that samples in quick mode.

**Phase 3: polish.**
- The setting's name, values and tooltip in all 13 languages (`make i18n MOD=mods/square_organic_towns ARGS='--check
  --lint-modinfo'`), tooltips wrapped (`make tooltips`).
- A Changelog entry and a revision bump in _metadata/description.html, plus one line about the new behavior in the
  description.
- The Dev companion (square_organic_towns_dev): a readout of each town's R/C/I shares and supply weights so a run can be
  checked by eye.

End: `make gate MOD=mods/square_organic_towns` once, then a short in-game test plan in TESTING.md: a new map with one
town fed only industrial cargo and one fed only passengers, then compare their mixes after about 10 game years against
a second save on Game default.

Done offline (2026-10-15; PLAN.md 6.2 "Supply-driven district weighting"):
- DONE plan + build: ot_rci (pure: the base usage formula, smoothing TAU 0.5 years, aim FLOOR 0.12, the step: budget
  = the target's growth (STEP_MAX 0.03 per game month), the initial sum kept (the base game's speed), built floor,
  CEIL 5 % over n0, TOTAL_DEV 4 %, never past the aim), ot_engine.townSupply (town_util.getCargoSupplyDemands +
  getTownLineUsage), Driver:rciTick / rciTown (one town per step, 4 per tick, 2 ms, one command, never beside a job),
  the one writer E.setInitialCaps, the FILL restore exact for weighted towns (`rci=keep`), the level weights put back
  after a write (§58 refill for managed towns), saved `rc` (EV_RCI, additive), the setting `town_growth`.
- DONE visual tie-in: the lean (55 / 52 / 45 %) multiplies the Works / district / lane-ahead draws; a commercial lean
  doses its core as a densify town.
- NOT DONE: the starting-size evening (a no-op under the built floor; the user's call).
- DONE polish: 13 languages, tooltip wrapped, Changelog, dev ALLTOWN `rci=` and the inspector line.
- Tests: test_rci (15).


## 67. Lock the game's own streets after it builds them; steer with a few unlocked valves (2026-10-15; done offline 2026-10-15; run `2026-10-15_0759_rci-sqrl` load 2 (seed `a`, EU, 1900, Quick 40 years; HISTORY.md); details PLAN.md 6.2 "Game-street locking and valves"; in game: TESTING.md "Combined test iteration" step 16)

The user (2026-10-15): "lets try locking the games streets after it builds them. then we try to steer early building
with locked streets, and intentionally build unlocked streets at the opportune places." With §65 the game still built
58 % of the non-core edges (1704 game / 1231 mod, per town 0.35-0.81): it branches off the unlocked core and then off
its own new unlocked streets.
- DONE API: no in-place setter for `roadDevelopmentLocked` (findings towns.md: SimpleStreetProposal has add / remove
  lists only, no edge-update command, the base tools' StreetEdgeNodeModifier is a GUI construction action). A game
  street is rebuilt between the same two nodes, locked (ot_engine `lockProposal`, move_it's pattern; end node configs
  re-pointed; no node rebuilt).
- DONE lock (ot_glock, Driver §67): the town's houseless game streets (and the core's: `CORE`), settled `SETTLE_S` 3 s,
  no stops / constructions / bridges / tunnels / loops / short edges / other towns' streets, not in a valve zone;
  queued at the CHECK (8 at most, tips first), locked when the job ends (stages glock / glockWait), a refused batch
  edge by edge, refused edges counted (2: left alone), the town backed off (60 s doubling to 1800, 8 in a row: off),
  600 per town and 6000 per session at most. `WITH_HOUSES` false (constant) until the console probe answers.
- DONE valves: 1-3 per town (organic 2, grid 1, + 1 big, + the stall guard's), anchored on unlocked streets out at the
  rim toward the §62 lean / §63 arms, never toward dense forest (skeleton clearance), water or a neighbour's gap; the
  game's new streets within 300 m stay open until 14 (organic) / 8 (grid) of them, 24 checks or the anchor is gone, then
  locked and the next valve opens elsewhere (a closed heading rests). No good anchor: the next mod build leaves one
  outward tip toward the best heading unlocked (a stub valve).
- DONE supply: the stall guard's fire also opens one more valve (at most 2), before level 3 relaxes the forest hold.
- DONE saves: frame `gk` (old frames: the §65 lock only), `gx` the rebuilt ids; additive.
- DONE logs: GLOCK (send / per edge / backoff), VALVE (open / close / want), CHECK `valves= glocked= gameOpen= glock=`,
  STREETS `gameLock= valves= glocked= gameOpen= glockedSession=`, STALL `valveExtra=`.
- DONE console probe (TESTING.md step 16): rebuilds one housed street near the camera, locked, and prints its houses
  before / after.
- Tests: test_glock (20).
- Open: houses after a rebuild (the probe); the rebuild's cost to the player; the game's branches off housed unlocked
  streets and off a fresh street before the next check; the valve constants are offline guesses.


## 68. Small follow-ups: Quick moves the calendar, independent decision draws, company towns, the lock's refund (2026-10-15; done offline 2026-10-15; details PLAN.md 6.2 "Small follow-ups (§68)"; in game: TESTING.md "Combined test iteration" step 17)

Approved by the user as recommended (2026-10-15), details decided offline:
1. **Quick moves the game date by default (dev).** Every Quick run logged `moveDate=false`, a 1900 calendar for 40
   simulated years, so the era rules never saw the real year.
2. **Decorrelate the remaining seeded draws that are shifted copies.** §64 found `ot_rng.hash` affine mod 2^31 - 1
   (equal-length labels: one draw shifted) and fixed only the offshoot decisions. Audit every `rng.unit(seed, label)`
   decision, switch the coupled gates and kind picks to the non-linear draw, keep geometry jitter, show before / after
   on 20000 seeds, keep saved picks on existing maps.
3. **Company towns actually appear.** §62: 0 company towns on 23 archived loads (heavy works 1236-1577 m from the
   starting towns; the pick needed ~1275 m). Full within ~1 km, the pick threshold at ~1.7 km (medium shorter), the
   slope rule kept unless the archived towns show many near-misses.
4. **Note only:** deep forest towns can be the biggest town on the map; an open item for the user. Also into PLAN's
   open items: §66's starting mix not evened out; §67's rebuild cost (made free or refunded if a safe, simple way
   exists, else open).

Done offline (2026-10-15):
- DONE 1: HUD `simMoveDate` true, otd_hudview / otd_runner nil = on (SG.new keeps its explicit off); the checkbox
  tooltip says ON (default). `Sim:moveDateNow` is forward only. With the calendar moving ot_satpace's slots add the
  game years (as in normal play); nothing else assumed the frozen date.
- DONE 2: `rng.decide(v, ...)` (rng.draw; v 1 = rng.unit) for forestMode, forestDeep, entryTrees, leadLane, leadEnd,
  bridge, metro, metroVariant, polyCore, satellite, shoreForm, arms3, fingers, densify, motif / motifPick and
  satpace ready / min / step / every / phase; charPick's jitter rng.draw. Anchors kept on rng.unit (one per group):
  shape, form, siteStyle, characterForm, characterIsland. Saves: frame `dv = 2` from now on; a frame without it keeps
  rng.unit for its re-derived picks (style.drawV 1); saved decisions (fd, ck, dz, sk, s, st, f, mo, cm) are read back.
- DONE 3: `CH.companyDist` (full within 1000 m, 0.4 at 1700 m for heavy, ~1545 m medium, read within 2200 m), slope
  0.05 kept. Archived maps 2026-10-13..15: 0 -> 5 of 16 distinct maps with an eligible starting town (not seed `a`).
- DONE 4: PLAN.md "Open decisions for the user" (deep forest size, §66 starting mix, the no-player build).
- DONE refund: the lock rebuild's charge (balance change, at most its cost, within 0.5-1.5 x the cost) booked back as
  street construction income; `GLOCK event=refund`, STREETS `glockRefund=`. A build without `ctx.player` (maybe free)
  stays untried.
- Tests: test_draws (6), test_character (+1), test_glock (+2), test_hud (the default); re-baselined: harbour cove
  signature (without motifs), NA_GRID fingers (the drawn count), the maturity model (withLegacyPods).


## 69. Steering lock: lock many streets, not all; locked branches with open tips; no bare spikes, rakes or zig-zags (2026-10-15; done offline 2026-10-15; run `2026-10-15_1936_sqot-glprobe` load 2 (seed `a`, EU, 1900, Quick 40 years, calendar moved; compare page `compare/2026-10-15_a-lock`, runs 0539 / 0629 / 0759 / 1936; HISTORY.md); details PLAN.md 6.2 "Steering lock policy (§69)"; in game: TESTING.md "Combined test iteration" step 18)

The user (2026-10-15), verbatim: "i think we should not lock all roads, just many of them, especially early when trying
to stear direction. but building a locked branch out into an open space, then unlocking at the end seems good. build
next phase now with your findings"

Findings from 1936 (§67 + the housed lock) against 0759 (§65 only): game-built share of the non-core edges 0.22 (was
0.58), forestLot 34.7 ha (46.9), forestCut 0.124 (0.172), capacity 98 % at year 40 (same), buildings 9709 (10480;
bigger era buildings), 1080 game / core edges locked by GLOCK, valves 86 open / 61 close, no stalls. Shape review of
the shots (0539 vs 1936):
- Better: tidier towns (Shaw from a spidery blob with long dead-end arms to a compact core with clear arms); the
  game's own fill as one or two patches where valves were open; water and open land read better (Merehythe along its
  shore, Seven Oaks south into open meadow); no bare X satellites.
- Worse: (1) bare locked spikes: a V-shaped spike south-west of Shaw, two ~600 m roads south of Seven Oaks, a straight
  ~1 km road from Merehythe over a bridge to the north peninsula; houses fill by network distance, so these stay
  empty. (2) Rakes / zig-zags: comb-like parallel dead ends on Seven Oaks' south side, its east arm zig-zagging into
  the woods. (3) Less organic texture: with the game confined to valves, most of the town is our more regular
  pattern. (4) Two Waters' south still grows into clearings close to the woods.
From the log: the arms' housed front was the farthest housed street along the arm (PLAN `armBuilt=`): Merehythe's arm
1 went 204 -> 904 m once a few houses stood far out (the bridge end's dose), so the arm ran out bare to them; Seven
Oaks' own unhoused streets (`ownEmpty=`) reached 1-2 km; the lead limit (`MAX_LEAD_M` 400 m from any street with a
house) let pieces run 238-391 m past the houses (`origins=...@far=`).

Asked: (1) selective locking (many streets, chiefly early and where direction matters; inside the established outline
open for the game's fill; game streets locked only at the outline toward unwanted directions; the share falling with
maturity; a small set of constants, `lockShare=` per town; legacy and mod kept for A/B); (2) a locked branch into open
space with its far end open, the valves tied to these tips; (3) no bare spikes (lead cap ~150-250 m beyond housed
streets, extend when the near part fills, the head start and skeleton reach bound; bridges / links need a target or a
length cap); (4) no rakes / zig-zags (join parallel spurs into blocks, limit an arm's turn and wiggle, find why the
look rules missed Seven Oaks); (5) tips clear of forest; (6) logs; (7) tests; (8) docs.

Results (2026-10-15, offline):
- DONE `ot_lockpol` (new, pure) and the "steer" lock (`D.LOCK_DEFAULT`, frame `lm = 2`): mod streets locked when they
  face forest / water / a neighbour's gap / (at the rim) against the land lean, lie in a skeleton arm while young, lie
  beyond the outline, or beyond the inner zone (0 young -> 0.85 x the outline grown); else open (fill). Game streets
  locked only at or beyond 0.85 x the outline when facing something unwanted, or beyond it while young. "mod" and
  "legacy" stay (`ot_hooks.lockDefault`, the frame); old saves keep theirs.
- DONE tips (`ot_glock.pickTips`): a locked branch's outward dead end left unlocked (65 m+ from dense forest, nothing
  unwanted ahead, valve separation, the wanted valve count), opened as a `kind=tip` valve; steer towns pick no game
  anchor and no stub.
- DONE spikes: `leadCap` 2 blocks within 150-250 m from streets with 2+ buildings (plans and the head start), the
  continuous arm front (gaps of at most a block), the skeleton's arm lead capped; bridges of steer towns need a target
  (houses / industry / a town on the far bank or ahead) or at most 220 m (Merehythe's 270 m crossing now needs one).
- DONE rakes / wiggles (ot_select, steer towns): a third parallel spur waits, a join of two parallel spurs' tips is
  cheap and free of the lead / lasso / empty-loop holds; an extension of a dead end turns at most 40 deg and not back
  against the street's last corner (sum over 55 deg). Why the zig-zag rule missed the east arm (from the code): it
  sees corners only at two-street nodes one edge back (a piece split into edges, or lanes at every spine node, hide
  the chain) and only turns over 35 deg.
- DONE logs: CHECK `lockShare= tips= gameKept= outline= lockMat=`, PLAN `lockMode= spikeTrim= leadCap= rakeHeld=
  rakeJoin= wiggleHeld= lookRelax=`, BUILT `steer= tips= tipRej=`, BRIDGE `target= len= noTarget=`, STREETS `lockSteer=
  lockShare= tips= spikeTrim= rakeJoin= wiggleHeld=`.
- DONE dev: the showcase's EU organic twin runs "mod" (lock all) beside the default steer row.
- DONE docs: the mod description's lock paragraph (it still said every street is locked) and the removal note.
- Tests: test_steer.lua (new, 19), test_driver (+1; §65 tests under "mod"), test_glock (§67 driver tests pin "mod"),
  test_demand (head start lead), dev test_layout / test_showcase.
- Not done / open: no offline replay of seed `a` (the logs hold no per-edge geometry); all constants are offline
  guesses for the in-game run (game share 0.35-0.5, forestLot <= 34.7 ha, no bare spikes); lead lanes (country lanes
  by design, `axis` targets) unchanged; the retire rule for empty dead ends unchanged (the lead cap now stops them
  earlier).

## 70. Tuning the steering lock: maturity sooner, no knotted curves, clearings between woods (2026-10-15; done offline 2026-10-15; run `2026-10-15_2031_sqot` (seed `a`, EU, 1900, Quick 40 years, calendar moved, lock=steer; compare page `compare/2026-10-15_a-lock`, run mod-69; HISTORY.md); details PLAN.md 6.2 "Steering lock policy (§69)", "§70"; in game: TESTING.md "Combined test iteration" step 19)

The user (2026-10-15): "yes tune it".

Findings from 2031: game-built share of the non-core edges 0.24 (target 0.35-0.5), following the §69 maturity
(`lockMat` on CHECK): the grown towns (lockMat 0.96-1.0: Two Waters 0.63, Dovemouth 0.68, Merehythe 0.57) let the game
fill; towns read as young at year 40 (lockMat 0-0.16: Holtbottom 311 buildings, Dalemere 534, Shaw 473, Little
Dalemere 431, Norfield 462) stayed 0.00-0.34. forestLot 32.2 ha, no stalls, spikes or rakes. Shots: Merehythe's south
has tangled crossing / near-overlapping curved locked streets (knots); Two Waters' south still grows into clearings
between woods.

Asked: (1) maturity sooner (size and age blended with the persons measure; mid-size towns open inside, young / small
ones steered; target game share 0.35-0.5 with forestLot <= ~34 ha; log the parts); (2) no crossing / knotted curves (a
look rule against crossings off a shared node, long near-parallel runs within a lot depth, small loops; relaxed only
when the increment would be empty; `knotHeld=`); (3) optional: clearings between woods count as forest-facing; (4)
tests; (5) docs.

Results (2026-10-15, offline):
- DONE lock maturity (`ot_lockpol.maturity`, Driver:steerNote `s.lockMat`): the larger of the persons measure, size
  (buildings 150..600 x the style / era scale) and age (years since the first frame 5..35, at most 0.8, gated by
  buildings / 450). Why the 2031 towns read young: the persons measure (1800..3600 persons) with the era's small
  houses (3.8-4.6 persons per building): 1233-2089 persons at 311-534 buildings. The frame saves its year (`fy`); frames
  from before have no age part. `s.mat` is the densify draw's level maturity again (§69 overwrote it). CHECK
  `lockMat=<v>:size<a>:age<b>:base<c>`. The 2031 towns at year 40 with the new formula (base -> new, innerK):
  Dalemere 0.12 -> 0.85 (innerK 0.00 -> 0.85), Shaw 0.10 -> 0.80 (0.85), Norfield 0.16 -> 0.80 (0.85), Little
  Dalemere 0.10 -> 0.77 (0.84), Holtbottom 0.00 -> 0.55 (0.57), Ashgrove 0.00 -> 0.51 (0.50), Wheatden 0.37 -> 1.00
  (0.23 -> 0.85), Watersmeet 0.53 -> 0.88 (0.53 -> 0.85), Hornholt Isle 0.54 -> 0.79; the grown towns unchanged.
  A 300-building town at year 20 reads 0.33 (innerK 0.16): still steered.
- DONE knots (`ot_knot`, ot_select `M.KNOT`, steer towns): a piece crossing a street or a chosen piece off a shared
  node, running beside one (within 0.65 x block depth, 20-35 m, for at least a block length, under 25 deg), or closing
  a loop under half a block waits; on the curves (the old tests compared chords and the piece's middle point, and left
  out every street at its end nodes). Relaxed only when the increment would be empty. PLAN `knotHeld=<n>:<cross>/
  <parallel>/<loop> knotRelax=`, STREETS `knotHeld=`.
- DONE clearings (`ot_skeleton.corridorAt`): woods on both sides ahead within 220 m in all face forest (LP.facing, mod
  and game streets) and reject a tip (`tipRej=corridor`).
- Tests: test_knot.lua (new, 8); test_steer's driver helper sets `lockMat`.
- Open: high-maturity towns with low game share in 2031 (Far Ashworth 0.90 / 0.15, Seachurch Cove 0.97 / 0.05, Lower
  Arunmouth 0.91 / 0.04, Hornholt Isle 0.54 / 0.00): their streets face forest / water / the lean (BUILT
  `steer=forest:n` dominates), which the maturity does not change, so the map share may stay under 0.35 even with the
  mid-size towns open; the corridor rule locks a little more. If the run shows it, the next lever is the face probe's
  reach (`AHEAD_M`, `CLEAR_M`) for inner streets. All constants are offline guesses; no offline replay of seed `a`.

## 71. Small tuning: small woods don't face forest, no curled hooks (2026-10-16; done offline 2026-10-16; run `2026-10-16_0405_sqot` (seed `a`, EU, 1900, Quick 40 years, calendar moved, lock=steer; compare page `compare/2026-10-15_a-lock`, run mod-70; HISTORY.md); details PLAN.md 6.2 "Steering lock policy (§69)", "§71"; in game: TESTING.md "Real play (first)")

Findings from 0405: game share 0.32 (target 0.35-0.5), forestLot 35.8 ha. Every town over ~400 buildings reads mature
(lockMat 0.74-1.0) since §70, but some still let the game build little because §69's face rules lock their rims: Shaw
0.07 (in a patchwork of small woods: mostly our locked radial spokes, two bare-ish arms W / SW, a hook NE), Dalemere
0.12, Seachurch Cove 0.15, Little Dalemere 0.15, Norfield / Watersmeet 0.19. A few small curled "P" dead ends in
Merehythe and Shaw.

Asked: (1) small woods don't count as forest for the face rules (the lock policy's face probe, the corridor, GLOCK and
the tips; a wood counts at ~1.5-2 ha; the §63 skeleton clearance and forest-hug costs unchanged; `smallWood=`); (2) no
curled hooks (find the source; hold a dead-end piece that curls over ~120 deg or comes back within a block depth of its
own street; relax only when the build would be empty; `hookHeld=`); (3) tests; (4) docs, the real play-through next.

Results (2026-10-16, offline):
- DONE small woods (`ot_forest.woodSizes / bigWoodAt / bigWoodNear / bigWoodBy`, `LP.SMALL_WOOD`, `GL.SMALL_WOOD`): a
  wood = a 4-connected patch of dense cells (one capped flood fill per grid, cached; a patch at the grid's border counts
  as big); the face rules count patches of at least `WOOD_MIN_HA` 1.75 ha (7 cells of 50 m): LP.facing's probe ahead,
  clearAhead and the §70 corridor (mod and game streets), a hug town's facesForest (a big wood within 60 m of the
  street or its tip probe; deep towns unchanged), the valve score and the tip checks. ot_skeleton's clearance helpers
  take an optional `isWood` predicate; everything else (skeleton, hug costs, budget) reads the plain cover. BUILT
  `smallWood=` (the build's streets and tips), CHECK `smallWood=` (rim game streets).
- DONE hooks (`ot_knot.hook`, ot_select `M.HOOK`, steer towns): source (likely, from the shots and the code; no per-edge
  geometry in the log): our plain small pieces, no motif built there; a dead-end chain grows a piece at a time, the
  wiggle rule only checks main / medium pieces and the knot rule only loops, so it curls round over several
  increments. Once the increment is chosen, a chosen piece whose far end is a new dead end is left out when the
  dead-end street it makes (the piece plus the chain behind it
  back to its junction, existing streets and this increment's pieces, at most 8 edges / 400 m) turns over `HOOK_DEG` 120
  deg over its last 150-250 m (signed) or its end comes back within a block depth (30-50 m) of its own chain, or,
  heading toward it, of its junction's other streets, after 3 x that of chain (tested at the end, so a U closing a
  block within one increment is fine); the select then runs once more without them. Connector / ring pieces and
  switchbacks / hill_climb and grid growers (NA grid, strict grids: their acute V spurs close into blocks; pruning
  them sent test_demand's NA grid seed 1 from 11 to 3 builds) exempt; kept when pruning would empty the increment. PLAN `hookHeld=<n>:<turn>/<back>
  hookRelax=`, STREETS `hookHeld=`.
- Tests: test_tune71.lua (new, 8); test_knot's off-switch case turns M.HOOK off too; test_demand unchanged.
- Next: the real play-through (TESTING.md "Real play (first)", its "What to watch" lists §61-§71). The seed `a` check
  is optional now (expect Shaw / Dalemere / Little Dalemere game share up, forestLot within ~36 ha, no hooks).

## 72. Name lists from other mods: their region by name, satellite towns in their language (2026-10-17; done offline 2026-10-17; player question on "Deutsche Städte und Gemeinden" (mod.io german-cities-and-municipalities5, modId unknown); details PLAN.md 6.2 "Name lists from other mods (§72)"; in game: TESTING.md "Name lists from other mods")

A player uses a German name list from another mod and asked whether "Town style: Automatic" and "Vanilla town street
angles: Automatic (by region)" recognize Germany. Found: `ot_inputs.NAME_RULES` matched raw substrings of the nameList
path (`<modId>::/names/<dir>/<file>.names`), so only "germany" / "europe" etc. hit; `german_cities` or `deutschland`
fell back to the climate (dry -> MED, subarctic -> NORDIC, else EU). The country only matters for France
(roundabout year, ot_character / ot_ring) and Spain (MED_ENSANCHE). Landscape / stop names already leave a modded list
alone (`ot_names.basePath` -> nil, "notBase"); keep that. The bug: the Works / districts the mod founds
(`Driver:offshootName`) got English composed names on any modded list ("Ulm Heights", "Freiburg Works"), since
`nameCls` fell back to "usa" / "en"; on a list without a classifier English words were glued onto native names
(the "High Wuhan" problem base lists avoid with an unused name of the list, `offshootListName`).

Asked: (1) detect a modded list's country / language from the path's words (split on non-letters, English and
native forms; base lists and square_names_us_ / ca_ unchanged; most specific match wins); (2) satellite names in the
list's language: the country's classifier, else a confident cheap guess from the map's town names (or skip and say
why), else unused names of the modded list's own towns.lua (pcall, capped), else today's composed English (logged);
never rename the list's towns; (3) one `[SQOT] NAMELIST` line per session; (4) tooltips only if needed; (5) tests;
(6) a TESTING.md item and a console line.

Results (2026-10-17, offline):
- DONE detection (`ot_inputs.NAME_PREFIX` / `NAME_WORDS` / `pathWords` / `wordRule` / `region` -> region, country,
  word): the lower-cased path split at every non-letter (UTF-8 bytes count as letters), exact words plus a few long
  stems (deutsch, german, osterreich, francais, nederland, italian); our state mods' prefixes first, then a country /
  language word over a continent word, the later of two country words. New countries: austria, switzerland, uk,
  ireland, belgium, czechia, greece, denmark, finland, australia, newzealand. Not matched on purpose: america(n)
  ("South American" lists), two-letter codes except us / uk. Base lists and our state mods: same region and country
  as before (test against the old rules).
- DONE satellite names (`Driver:listLang`, once per session; `ot_names.COUNTRY_CLS / countryCls / guessCls /
  moddedTownPaths`, `ot_engine.townListAt`): country -> classifier (germany / austria de, france fr, england / uk /
  ireland / australia / newzealand en, usa / canada usa, netherlands nl, italy it, spain es, portugal pt, sweden sv,
  norway / denmark nb, russia ru or ru_r and japan ja or ja_r by the map names' script); else a guess from at most 60
  map town names (Cyrillic / Japanese script -> ru / ja; else the site-tag share per classifier: best >= 0.3 and
  >= 2 x the runner-up, only en / de / fr / nl / sv; it / es / pt never, they score low and alike and the ja_r rules
  tag their endings; measured over the base lists, 300 draws of 16 names: wrong < 0.5 %); else the list's towns.lua
  at `<modId>::/names/<dir>/<lang>/towns.lua` (the game language's folder, its 2 letters, the country's folder, en,
  common ones; at most 12 pcall'd requires) and offshoots take unused names of it; else the old composed names. A
  list used up falls back to composed names too (`NAMELIST event=listUsedUp`, once). Base lists unchanged.
- DONE `[SQOT] NAMELIST list= base= region= country= regionSource= nameRegion= word= cls= clsSource=
  (base|country|guess|list|fallback) guess= listPath= listN= tries= why=` after INIT when the mod is on.
- DONE tooltips: "Town style" and "Town and stop names" got one sentence each (13 languages).
- Tests: test_namelist72.lua (new, 12).
- Open (in game): TESTING.md "Name lists from other mods" (a missing towns.lua only raising a Lua error under
  pcall is not verified in game).

## 73. Continuous thoroughfares: medium / large streets only as long, anchored runs (2026-10-17; done offline 2026-10-17; user report on early (~1909) towns; details PLAN.md 6.2 "Continuous thoroughfares (§73)"; in game: TESTING.md "Continuous thoroughfares")

The user: "The main issue I encounter is early on (~1909) medium streets get built in weird configurations (like just
a single track in-between small streets) and causes the car path finding to go in weird roundabouts. The whole point
of the larger streets is intentional thoroughfares where it would make sense." Before: "let's make it so the game
doesn't auto-build medium or large streets. it's too inconsistent. small town streets like base game." Agreed:
medium / large only as deliberate, continuous through routes; everything else small (xsmall where a style uses it);
the base game's sim templates stay (findings towns.md: removing them crashed town development).

Asked: (1) diagnose which code path makes an isolated medium edge around 1900-1920, with evidence; (2) a run rule:
one continuous chain, a minimum length, meaningful ends (exit, centre, station, another main run), no stub from a
partly built run; joins don't spread templates; an early-era choice; the same rule for late / metro arterials; a
remedy if the game's growth is a source, without removing sim templates; an audit token; tests; docs.

Results (2026-10-17, offline):
- DONE diagnosis. The logs can't name a single medium edge: no line lists town street templates per edge (ROADS
  `wide=` leaves `town_*` out). What they show: in `2026-10-16_1846_sqot` (seed `a`, EU, 1900) 17 PLAN lines with
  `hier=wide1..4` and BUILT `mix=0/9/91 ... 0/71/29` on 4-17 edge increments (e.g. `PLAN town=60267 edges=10
  hier=wide1/...`: one medium edge in ten; `BUILT town=60262 ... mix=0/71/29 townMix=0/16/84`); `2026-10-18_0122_sqot-sqrl`
  (old templates, era 2: the user's early play) built only small (`mix=0/0/100`, 7 builds), so its medium streets came from earlier builds, the
  game core or the game's own growth (unknown: now logged). The code path, reproduced offline: `ot_core.hierarchy`
  kept any main piece whose plan line goes on (`ot_select.through`) and that meets a street, however little of the
  line was built: EU organic spokes (`sp<i>:<ring>#<n>`, 25-56 m pieces) came one or two per increment, scattered;
  EU organic 1905 on a vanilla core after 6 increments: 4 medium runs of 7 edges, the longest 92 m, one a single edge
  (test_runs growth sweep with `RUN_RULE = false`). Second leak: `ot_proposal.build` gave an edge joining a dead end
  that dead end's template, so a small street continuing a medium dead end became one medium edge.
- DONE run rule (`ot_core.continuity`, `wideRuns`, `runAnchor`, `narrowTemplate`; in `hierarchy` and again in
  `Driver:plan` after the straight guard and forest lanes): a new wide edge's run (connected medium / large edges,
  existing + new) >= `RUN_MIN_M` 300 m and anchored (existing wide street, country road, centre or station within
  150 m; the late hierarchy also any existing street), else the narrower template. A build is all or nothing and
  a refused one is replanned (rule again): no partial stub.
- DONE early era: before 1940 (old templates) a separate new run only while the town has fewer than `RUN_OLD_MAX` = 1
  runs of 300 m (the high street); extensions go on. Choice: a town of ~1900 had one high street, the road through
  it, and narrow lanes; the user wants "small town streets like base game".
- DONE joins: `ot_proposal.narrowJoin` (a narrower town street at a medium / large dead end keeps its own template).
- DONE game growth precaution (unverified as a source): no §69 tip / §67 valve stub on a medium / large edge
  (`ot_glock.NO_WIDE_TIPS`, BUILT `tipRej=wide:n`). Sim templates untouched.
- DONE logs: PLAN `hier=.../short<n>` and `runs=<kept>/<cut>/<longest>`, SNAPSHOT `wideRuns=` (runs, edges, length,
  short, lone, longest, by builder mod / game / other), STREETS `wideRuns=` (summed). The audit lives in the town
  state as `wideRuns` (first stored as `wide`, which clobbered the 2 km site survey `ot_terrain.wide`; and
  `streetsNote`'s local `core` count shadowed the `ot_core` module, so the STREETS line raised in the assess stage:
  test_demand EU frontage built nothing). Both fixed 2026-10-17 (`D.wideAuditText`; regression test in
  test_namelist72 "STREETS line with a town's §73 run audit").
- Tests: test_runs (new, 11), test_hierarchy / test_proposal updated, three geometry thresholds relaxed (test_head,
  test_shore, test_skeleton; the narrower streets shift footprints).
- Not done: built medium edges in existing saves are left as they are (no rebuilds; a short one joins a run only when
  a build makes it 300 m with an anchor).
- Open (in game): TESTING.md "Continuous thoroughfares" (lone medium edges and car detours gone; whether the game's
  own growth builds medium streets: SNAPSHOT `wideRuns=...;game<n>`).

## 74. Close the gap: near-miss dead ends joined to the street ahead (2026-10-17; done offline 2026-10-17; user shots of an EU organic town at a forest edge, ~1900s; details PLAN.md 6.2 "Close the gap (§74)"; in game: TESTING.md "Close the gap")

The user (2026-10-17): "Is it feasible to have our roads connect to each other slightly more logically when they are
so close? I like the loose and organic, but sometimes it feels a little too random, and would make more sense if they
were auto-connecting a bit more often." The shots show (1) two dead ends curling past each other ~20-40 m apart, (2) a
stub running beside a street, ending ~10-30 m beside a junction / the street, (3) a stub ending a few metres short of
a street's side, pointing at it (an obvious T).

Asked: (1) diagnose why, with evidence; (2) join near-miss dead ends (mod- or game-built; adding streets only) within
~80 m roughly ahead: a T on the other street (3), a bend meeting another dead end (1), a join at a node near a junction
(2); base street limits, no buildings / tracks / constructions, sane junction angles and spacing, the §70 knot rules,
gap lines, no bridges, the §73 width rule, the lock policy; (3) organic: a seeded chance rising as the gap shrinks,
forest dead ends partly left, a per-increment cap; (4) existing saves; (5) a per-town log with reasons; (6) tests incl.
a growth sweep; (7) docs.

Results (2026-10-17, offline):
- DONE diagnosis (from the code; the logs hold no per-edge geometry, so no shot can be traced to a builder or a rule):
  the planner joins only existing DEAD ENDS (ot_plan join "deadEnd"; the in-game-verified D3 joint is a dead end's,
  findings towns.md), and the selector's pieces come from the master plan's lattice, which knows nothing of the
  streets already there. A piece whose middle lies within occR (8-30 m) of a street or that crosses one is blocked
  (ot_select.classifyPiece), a planned edge within clearEdge (16 m centre line: ~8 m of open ground between two small
  streets' kerbs) of a street it doesn't meet is dropped (`nearExisting`), a new node within 6 m of a street is
  refused (`blockedNode`); a dead end joins another only when a lattice junction lies within snapR (8 m) of it, or
  through a connector to a lattice junction (ot_select CONN_*). So every lattice front that meets an existing street
  stops one piece short (case 3: the 16 m rule leaves exactly the "few metres" of kerb gap), and two fronts from
  different lattices pass each other (case 1). §69's lead cap / wiggle (40 deg) and §71's hook rule stop extensions
  that would have curled in. The game's own growth adds cul-de-sacs (findings towns.md: "loops and cul-de-sacs at its
  edge"). Evidence in the logs: `2026-10-16_1846_sqot` PLAN lines (empty plans) list `dropped=nearExisting` 16x and
  `blockedNode` 12x, plus mixed; `2026-10-18_0122_sqot-sqrl` (the user's play) SNAPSHOT `deadEnds=30 joinable=25` for a
  190-edge town and only 7 mod builds in the session, so most of what the shots show was the game core / the game's
  growth (STREETS `coreEdges=637 modEdges=217 gameEdges=59`); which of the shown stubs is whose can't be told.
- DONE `ot_nearmiss` (new, pure) and the pass (`ot_core.nearMissPass`, after each increment's plan, also on a town
  held by its own empty budget; opts.nearMiss from the driver only): for each joinable dead end with another street
  within `JOIN_MAX` 80 m and `AHEAD_DEG` 60 deg ahead (smallest gap first), the nearest target nodes ahead: another
  dead end (a bend joining both, `pair`), a node in the middle of a street (`tee`), a small 3-way junction
  (`cross`, all arms small). Shapes (best first): the straight line, one circular arc (radius >= 78 m), arc-and-straight
  either way (100 / 150 / 240 m), Hermite curves; D's kink <= `KINK_DEG` 35, a pair's kink at N <= 35, a street node
  met >= `TEE_MIN_DEG` 50 off every street there. Place checks on the shape (buildings within 12 m of the curve, gap
  lines, industry zones, greens, country roads), then ot_plan with the one street (its angles, footprints, chord
  clearance, slope, water; ot_plan `joinExtra` lets the street end at that node), then on the planned curve: slope
  (node heights and ground, style.maxSlope <= 0.2), water, streets crossed or passed within 16 m, §70 parallel run,
  a loop under `LOOP_K` 0.25 x a block, another junction within 20 m of a street node. Chance: 0.97 up to 15 m,
  falling linearly to 0.15 at 80 m (the pair's draw is fixed per town seed: a pair left by chance stays left); in a
  big wood of a hug / deep town left with 0.5 / 0.75; at most 2 per increment, none touching a node the increment
  uses; joins planned together and checked against the increment's own new streets, then merged (`NM.merge`).
  Retired / otherTown / no-config dead ends stay out (their noJoin); forest lanes (country template) too.
- DONE driver: `Driver:midJoinOk` (a street node may be joined only with a node config, all its segments plain town
  streets of the snapshot, no track segment (`ot_engine.nodeSegmentCount`), not in a construction, this town; its
  join info goes to `job.nmInfo` and into the proposal's node info, so ot_proposal rewrites its config in the engine
  pattern over all three / four segments, as at a joined dead end). Joins are small streets (§73: never a wide edge;
  `narrowJoin` keeps them small at a medium dead end), keyed `nm:<D>:<N>`, so the lock policy treats them like any
  piece and a refused pre-check excludes them for the session. Time budget `D.NEAR_MISS_US` 8 ms per plan (the pass
  runs in one slice, inside a pcall; the hang guard's error passes through).
- DONE logs: PLAN `nearMiss=<found>/<joined>/<kept> nmKept=<reason:n,...> nmJoins=<kind:gap m,...> nmErr=`
  (also on empty plans), STREETS `nearMiss=<joins built>`. Kept reasons: inc, cut (2026-10-18), noJoin, lane, noNode,
  target, angle, curve, slope, water, gap, zone, green, road, building, cross, near, parallel, loop, spacing,
  footprint, plan, refused, forest, chance, cap, taken, conflict, budget.
- Measured offline (vanilla core + 7 increments, 6 styles x 3 towns): with every chance 1 and no cap, 71 of 195
  near-miss dead ends (36 %) are joinable; the rest `curve` 44, `noNode` 38 (no node of the street ahead in reach:
  a T on an edge's side would need the edge split), `target` 32 (4-way nodes, junctions with a wide arm), `loop` 6.
  With the chance and the cap (test_nearmiss growth sweep, 10 increments, full): dead ends with a street within 40 m
  ahead 91 of 568 (0.160) -> 64 of 493 (0.130); organic styles 0.127 -> 0.109, others 0.231 -> 0.184.
- Tests: test_nearmiss.lua (new, 18), test_driver (+1: the T through the driver, the node config in the spec, PLAN
  fields, midOk's refusals).
- Not done / open: a T on the side of an edge without a node (`noNode`) needs splitting that edge (remove + two edges
  + the T), which no build of ours has done; a locked same-geometry rebuild keeps its houses (findings towns.md), a
  split is untested (console probe first). Joining a degree-2 / 3 town node rewrites a config that has through
  connections: the same remove + add as at a dead end and as the Crossing Tool / Smart Lanes do on junctions
  (findings roads.md), but not yet seen for a street T in game (TESTING.md "Close the gap" 2). All constants offline
  guesses.
- Less cautious (2026-10-18; user: joins too rare to notice in game): kink 45, arcs 74 m, nodes to 100 m, 8 shapes on
  the place checks, chance 0.97 to 25 m -> 0.4 at 80 m, retired dead ends closable, `cut` reason; side T deferred.
  Details and offline numbers: PLAN.md 6.2 "Close the gap (§74)" "Less cautious".

## 75. By deliveries: residential keeps a quarter (2026-10-18; done offline 2026-10-18; user decision after reviewing §66; details PLAN.md 6.2 "Supply-driven district weighting" (Formula); in game: TESTING.md "Combined test iteration" step 15)

User: keep "Town growth: By deliveries", but a town fed only goods should stay a place people live in. With a 12 %
floor per district a goods-only town aimed at 12 % residential, made few passengers of its own and earned little
passenger experience; its commercial capacity relied on visitors from other towns.

- DONE `ot_rci.FLOORS = { 0.25, 0.12, 0.12 }` (R, C, I) replaces the single `FLOOR` 0.12. Aim w = FLOORS + 0.51 x e /
  Σe: residential 0.25-0.76, commercial / industrial 0.12-0.63 (was 0.12-0.76 each). Vanilla caps a district at 0.5 in
  a town; the 0.63 lean is still clearly lopsided.
- DONE test_rci aim cases (goods-only, industry-only, passengers-only, even).
- Unchanged: the step rate, the built floor (nothing torn down), the tooltip (it names no numbers).
- Not done: showing the lean in the town card (offered as item 3, not chosen).
