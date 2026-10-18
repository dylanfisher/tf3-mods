# Roundabouts Showcase (DEV ONLY, never uploaded)

`mods/square_roundabouts_showcase/` builds many Better Roundabouts (`square_roundabouts`) param
combinations across a map in a pattern (grid, quilt, kaleidoscope, mandala, spiral, ...), for
screenshots and visual regression checks. DEV markers as `square_roundabouts_probe`: `NOT_FOR_UPLOAD.txt`,
"DEV ONLY - NOT FOR UPLOAD" in modinfo and description.html, dependency on `square_roundabouts`, no
translations (DEV mods are exempt), no cover.

## How it works

Game script `showcase.gs.lua` -> `showcase.script.lua` `guiUpdate` (GUI thread, as the probe). No
game-script state: nothing is written to the save except the constructions it builds, and only when
"Run" is On and "Mode" is Build. Phases, one step per `guiUpdate`:

1. **init**: read mod params (`api.engine.config.getModParams`, 1-based). Off -> stop. Else wait "Start delay".
2. **setup**: resolve each entry's `.con` (`api.res.constructionRep.find`, as the probe), read its params
   **generically** from the rep (`desc.params[i].key / values / defaultIndex`) and its
   `desc.updateScript.fileName / params` (captureParams, e.g. the highway entries' `types`). New params
   (e.g. the Channelized Junction's Scale) are picked up without code changes. Offline (tests) the same
   model comes from the `.con.lua` `data()`.
3. **enumerate** (`sc_combos.lua`, pure): Showcase / Every combination (round-robin over entries, cap) /
   One param at a time / Random sample (seeded). Values are 1-based indices (TF3 construction params).
4. **measure**: each combo's footprint from the construction's own updateFn, resolved generically like
   base `util.useFn` (`scripts/util.tl`: `loaderHelper:useFn(ref)`, then the `game` table path) and called
   as `fn(captureParams, params)`; its `edgeLists` (position/tangent pairs) are sampled as Hermite curves.
   Every sample grows by **its own street's half width** (sum of the template's `laneConfigs` widths from
   `api.res.streetTemplateRep`, cached, one INFO line per template) + 4 m curb, plus a 1:1.5 earth slope
   x |z| where the street is raised and not a bridge (Hwy-level embankments); floor 6 m. Fallbacks: the
   geometry module named after the script, then a 400 m box (WARN). Only `sqrb_*` keys are enumerated.
5. **layout** (`sc_layout.lua`, pure; run in a coroutine that yields every 50 ms of CPU, `LAYOUT_SLICE`, so a
   big layout is spread over several GUI updates; if yielding fails it runs in one go): tight packing with exact oriented-box collisions (boxes grown by
   gap / 2, spatial hash `Packer`), then a final overlap check (tests require zero drops) and the Max
   radius. `LAYOUT` logs `fill=` (footprint area / bounding box) and `extent=`; `PLAN` lines + ASCII `PREVIEW`.
6. **build** (Build mode only): up to "In flight" (default 16) builds wait for their callbacks at
   once, but a placement is checked and sent only when its box grown by 50 m more (`FLIGHT_MARGIN`)
   touches no build still in flight: far-apart pieces build in parallel, neighbours one after another,
   so every `makeProposalData` check sees its built neighbours. The queue is interleaved over 1 km cells
   (`BUCKET`, strided cell order) so consecutive pieces are far apart; the first free one of the next 64
   queued pieces is taken (`WINDOW`), at most "In flight" checks per GUI update. Off-map / water corners
   -> skip; any error message, critical, collision or building -> refused, never forced. A refused or
   skipped placement moves to the nearest free spot (rays in 16 directions, its old spot stays blocked)
   up to 2 times (`RETRY` lines), except in a kaleidoscope (a moved copy would break the symmetry).
   Build: `api.cmd.makeWorldBuildProposalCmd(sp, ctx, false, true, false)` + `sendCommand` with a callback
   (GUI thread, as `square_smart_lanes`; never in build events). A build without a callback for 60 s
   stops the run. PROGRESS and SUMMARY log `buildsPerSecond`.
   One proposal per construction: `SimpleProposal.constructionsToAdd` is a list (api/type.d.tl) and a
   subscribed mod (undo_tf3_test player_assets) sends several at once, but the base game only ever sends
   one, and `ProposalData.errorState` is per proposal, so a refused batch could not say which piece was
   at fault. Parallel singles keep "drop only the offending piece" exact.
7. **summary**: built / failed / refused / skipped / retried / dropped, fill, top reasons.

Transforms: `Mat4f` from exact cos/sin (multiples of 90 deg exact), every component `-0` -> `+0`,
non-finite -> placement skipped (findings "Negative zero": +0 transforms are the safe ones).

## Road-shape collisions (`sc_shape.lua`)

The bounding box of a star-shaped roundabout is mostly empty corners, so the boxes are only the broad
phase. Each footprint also carries its road shape: probes every 6 m along every edge with their own
buffer (half street width + curb by kind + 1.5 x height for raised non-bridge roads), field segments
(3 probe steps, chord sag added to the buffer) and island outlines (ground faces; the inside counts as
occupied, the island has colliders). Per combo a sparse clearance field (5 m cells, built once,
lazily, to the range the layout needs) holds the distance to the buffered roads. Two placements whose
boxes overlap collide only if a probe of the shape with fewer probes lands in the other's field closer
than its buffer + gap + slack (3 m + the cell half-diagonal, conservative); when the probed shape has
islands, the other direction is checked too (a small piece wholly inside an island). Chunks of 8 probes
are culled by the field's bounds. Up to gap 40 m (`SHAPE_MAX_GAP`); larger gaps use boxes alone.

Search with shapes: kaleidoscope orbits try 12 rays across the wedge x 2 rotations (base, +90),
mandala / spiral 3 rays around the ideal angle x 2 rotations, nearest free spot along each (6-40 m
steps, then bisection). Grid / gradient / checkerboard are skyline-packed by boxes, then compacted:
every piece slides horizontally toward the centre line, then vertically, nearest first, to the closest
spot where its roads fit (per-band shift tracking keeps it fast). The mosaic keeps its patch seams.

Gap 0, radius 6000, Repeat, all 126 showcase combos, offline (Lua 5.4; time includes the fields):

| Pattern | boxes: pieces / road fill / time | shapes: pieces / road fill / time |
|---|---|---|
| grid | 976 / 22.9 % / 0.2 s | 1195 / 28.6 % / 1.7 s |
| mosaic | 661 / 22.4 % / 0.1 s | 661 / 22.4 % / 0.2 s (unchanged, seams kept) |
| kaleido4 | 1113 / 20.4 % / 0.9 s | 1561 / 27.1 % / 4.8 s |
| kaleido8 | 1713 / 20.7 % / 1.3 s | 2417 / 34.1 % / 6.3 s |
| mandala | 970 / 17.4 % / 0.6 s | 1733 / 31.2 % / 3.1 s |
| spiral | 1137 / 18.4 % / 0.7 s | 1998 / 33.0 % / 3.5 s |
| gradient | 620 / 23.3 % / 0.2 s | 725 / 32.1 % / 1.2 s |
| checker | 956 / 22.0 % / 0.2 s | 1178 / 29.2 % / 1.6 s |
| scatter | 1124 / 13.0 % / 0.2 s | 1840 / 22.1 % / 1.0 s |

Road fill = buffered road area / the layout's bounding box (the box fill can pass 100 % now). The
layout runs in the sliced coroutine, so these seconds are spread over GUI updates.

## Collision feedback and margin tuning

Build callbacks record their result entities (entity -> placement). A REFUSED / RETRY line lists
`hits=`: `id:<owner key>@<model clearance>m` for an entity one of our builds made (`(inFlight)` if
its callback had not come back), else `id:con(<file>)|edge|node|other`. The model clearance is
sc_shape's distance between the two buffered road shapes (positive = the model thought they were
apart). SUMMARY `collisionKinds=` aggregates per element kind of the tightest probe:
`highway:n5,min2.1m,raised3`. To tune: if a kind's refusals show positive `min`, raise its
`sc_footprint.KERB_BY_KIND` by about that much (raised>0: raise `SLOPE` instead); if hits are
`(inFlight)`, raise `sc_config.FLIGHT_MARGIN`. Target < 1 % refused at gap 0.

## Patterns (packed tight)

| Pattern | Look / packing |
|---|---|
| Grid | skyline packing, sorted by entry then size (each item its own size) |
| Mosaic | one skyline-packed patch per colour attribute (island / lanes / entry), patches packed with a gap + 10 m seam |
| Kaleidoscope 4 / 8 | dihedral D4 / D8: each combo's whole orbit (n rotations + n true mirror images: traffic side flipped, rotation 180 - theta since the mod mirrors x -> -x) goes to the nearest spot of its wedge (6 angles tried) where every copy fits; smallest in the centre. Every combo is placed (1 + 2n(N-1) constructions); only orbits past Max radius are dropped |
| Mandala | rings of 6, 12, 18 ... by size, each item at the nearest free spot on its ray (+- half a step) |
| Spiral | golden-angle order by size, nearest free spot on its ray (+- 30 deg) |
| Size gradient | skyline, small to large |
| Checkerboard | skyline, the two groups alternate (two entries, or the two traffic sides) |
| Scatter | seeded random spots in a disc sized for ~45 % fill, else the nearest free spot |

Rotation "Pattern" also lets the packer try each item turned by 90 deg (180 has the same outline).

**Fill: Repeat** (default): when the combos run out, the pattern goes on with repeats (proxies of the
same items in the same order, rotation drawn again for the random modes; whole orbits in a
kaleidoscope) until the Cap (then = total constructions) or the Max radius. Rectangle patterns pack a
2R-wide block of repeats and crop it to the disc. An item that finds no spot is retired (the free space
only shrinks), and repeat ray searches start near the recent placements, which keeps it fast. With
defaults (Showcase, All, Kaleidoscope 4, gap 10, cap 2000): radius 3000 m -> 593 constructions,
6000 m -> 1073. Layout time offline (Lua 5.4) at the largest cap 10000, radius 8000: at most 1.7 s
(kaleido8 with 600 small Magic combos), most patterns < 1 s; in game it is sliced over updates.
Fill at gap 10 for all 126 showcase combos, no radius limit (tests/square_roundabouts_showcase
test_layout.lua "density"; old = the first version's algorithm on the same footprints): grid 87 % (74),
mosaic 68 % (55), kaleido4 51 % (20), kaleido8 46 % (19), mandala 37 % (24), spiral 38 % (24),
gradient 78 % (27), checker 86 % (35), scatter 36 %.

## Later phases (not now)

- **Connect neighbours** (straight road between nearby free arm ends): needs the built nodes' ids from the
  callback's `resultEntities` and a street proposal per pair; risky (slopes, angles, collisions with
  slips). Not implemented.
- Camera fly-through / screenshot automation.

## Unverified (needs the engine)

- `desc.params` / `desc.updateScript.params` readable from `api.res.constructionRep.get` on the GUI thread
  (each entry logs an `ENTRY` line with its keys, value counts and defaults: check them on the first run;
  an entry with no params read builds only its defaults). Whether the rep's `defaultIndex` is 1-based like
  the `.con.lua` (an out-of-range one falls back to 1).
- `loaderHelper:useFn` from a game script's GUI state (an `INFO`/`WARN` line says which footprint path ran;
  `PLAN ... fp=updateFn|geometry|fallback`).
- Building a SimpleProposal construction from the GUI thread's `guiUpdate` (smart_lanes sends street
  proposals from there; constructions only from base/mission code).
- The footprint margin (street half width + 4 m + 1.5 x height): terrain cut/fill on uneven ground and
  bridge ramps may reach further; the sequential collision check is the safety net (refused, retried
  elsewhere, never forced).
- The mirror axis convention (x -> -x) for true kaleidoscope mirrors (from the geometry code, not seen in game).
- Money: a normal game may run out; use a sandbox / unlimited money (the refusal is logged).

## In-game runbook

**The defaults BUILD** (Run On, Mode Build, start delay 5 s, centre X / Y = 0 / 0): enabling the mod on
a game builds hundreds of constructions 5 s after loading. Only enable it on a throwaway Blank Slate map.


1. Use a **flat, empty map** (New game, flat terrain, no towns/industries if possible; sandbox / lots of money).
   The user links the mod (`make link`); enable "DEV Roundabouts Showcase" and Better Roundabouts.
2. First try, settings: Run **On**, Mode **Dry run**, Constructions **All**, Combinations **Showcase**,
   Cap **2000**, Fill **Repeat**, Pattern **Kaleidoscope 4**, Gap **10 m**, In flight **16**, Position **X / Y** (0 / 0),
   Max radius **3000 m** (593 constructions with repeats; the 60 biggest combos' orbits, incl. the
   highway interchanges, don't fit; **6000 m**: 1073, all but 9 combos).
   Load, wait for the start delay, then read `stdout.txt` (game folder, `grep SQRB-SHOW`): `ENTRY` lines
   (params found per entry), `PLAN` lines, the ASCII `PREVIEW`, and `SUMMARY`.
3. If the preview looks right, set Mode **Build** (the default) and reload. Watch `BUILD` / `REFUSED` /
   `SKIP` / `RETRY` / `DONE` lines, `PROGRESS ... buildsPerSecond=` and the final `SUMMARY`. If neighbours
   get refused for collisions, try In flight **1** (strictly one after another) to tell parallel effects apart.
4. Other looks: Mosaic + Every combination (cap 500), Mandala + Showcase, Spiral + Random sample,
   Checkerboard with Constructions = Ring (CCW vs CW alternate).
5. Turn Run **Off** afterwards (or disable the mod): it runs once per game load while On.
   Quit to the main menu before unlinking (findings: no mod removal in game).

Pattern previews: [PATTERNS.md](PATTERNS.md) (offline ASCII preview of every pattern).
