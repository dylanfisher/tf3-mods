# Better Minimap: performance review (2026-10-08)

**Verdict: no code changes.** The script is already change-driven and throttled. Every hot path costs
microseconds, or runs every few seconds or minutes. Nothing shipped changed, so the revision stays at 4.

## Evidence

- In-game log (`crash_dump/stdout.txt`, 2026-10-09 session, 15 towns, 54-60 industries, 541 `[Minimap]` lines):
  - `game changed` rebuilds came 1-6 minutes apart (25 in the session), each with a changed industry
    count (industries founded or closed by the game). Town revisions do **not** bump with growth or
    noise, so there were no rebuild storms. Each build: `makeMapFromGame` 10-20 ms, industries read 0.3-0.5 ms,
    preview `onReady` 40-250 ms after mount (the component's own latency).
  - `camera box ->` is logged only for the first 3 moves per overlay mount. The guard `sameCamPx`
    re-renders only on whole-pixel or whole-degree changes.
- Offline timing (lupa, Lua 5.4, scratchpad bench) of the 2 s revision check's Lua work (table
  build plus deepEquals, with 50 towns and 300 industries): 0.19 ms with 256 terrain entities, 0.54 ms with 1024,
  1.9 ms with 4096. Engine calls add to this. The terrain entity count per map is unknown, but the base map
  editor runs the same check **every frame** (map_editor.tl:308-345), which suggests the count is small.

## Hot paths examined

| Path | Frequency | Cost | Decision |
|---|---|---|---|
| 6 `onStep` closures (overlay, fit, rev, position, guard, preview-ready) | every frame | one ref read each, return early unless a timer flag is set | keep |
| Camera poll `readCamView` (getCameraData, 8 screen2World, getHeightAt, ~10 small tables, 1 pcall closure) | 10 Hz, only while shown | ~tens of µs | keep. Skipping the footprint when getCameraData is unchanged would save µs only |
| Overlay re-render (box + arrow re-mounted with new keys) | only on a whole-pixel or whole-degree move, ≤10 Hz | 2 small subtrees | keep (re-mount on move was required in game) |
| Revision check `readRevState` + deepEquals | every 2 s, only while shown | ≤0.5 ms typical, ~2 ms Lua at 4096 terrain entities | keep. An allocation-free in-place compare would be ~3x faster but is cold code. Revisit only if a huge map shows a 2 s stutter |
| Rebuild (`makeMapFromGame` + industries + preview/markers re-mount) | on a real change (minutes apart in the log) | 10-20 ms main thread + preview re-mount | keep. Reusing the map when only the industry set changed was considered, but founding an industry likely also changes terrain revisions (construction terraforming), so the fast path would rarely apply |
| Industry markers (one full-picture padded layer per industry) | built once per map gen and size | N mouse-transparent nodes | keep. The layout was chosen because h/v placement failed in game. Changing it is a crash/regression risk without measured gain |
| Position poll (2 getPosition, getSize, string.format) | 2 Hz while shown | trivial | keep |
| Fit check (log only) | 1 Hz while shown | trivial | keep |
| Guard tick (`currentPrefs` + 2 deepEquals on a 6-field table, isShown) | 4 Hz | trivial | keep |
| Caches: cargo icons, preview env, keep-mode, showArrow param | once | n/a | already cached |

## In-game checks (if a stutter is ever reported)

- [ ] Big map (16x16 km or more), window open, game running at max speed: a regular hitch every ~2 s? If so,
      the revision check is the suspect. Log the terrain entity count and move to an in-place compare.
- [ ] Frame rate with the window open vs closed on a map with 300+ industries (marker layer cost).

## Network layer (2026-10-09)

Revision 5 work in progress (not committed, revision not bumped). Goal from the user's SQPERF run: `net_render` under
~2 ms per call, no single onStep section over ~4 ms. Offline audit only (the game can't be run here); the next in-game
run fills the "after" column below.

**Runtime:** the game's Lua is 5.2 (`bit32` exists, react.lua uses `table.pack`/`table.unpack`, `math.tointeger` is nil),
offline tests run Lua 5.4 (lupa). Round 2's log puts the game at about the offline speed for raster/read and ~1.6x slower
for the encode (first build: encode 24.7 ms in game vs 15 ms offline for 512x512). No `table.new`: a table can't be
presized.

### Findings per section

| Section | Baseline (user, ~60 s) | Root cause (evidence) | Change |
|---|---|---|---|
| `net_render` | 23 calls, avg 6.6, max 8.4 ms | Each call built `builtin.ImageView{ data = table }`, and react.lua `makeUserdata` converted the 1 M-entry table into the C++ vector on **every** render (react.lua:155-205). The renders were not image changes: stdout.txt 06:37:21 window has `net_render n=13` = `canvas_render n=13` = `content_render n=13` with `net_publish c=3`; the next window 10/10/10 with no publish. Every MinimapContent render (Net/Ind/Hi-vis toggles, S/L, map rebuilds) re-renders the canvas and every child recipe. Camera moves don't (`overlay_render n=83`, own state). | Round 3: one params userdata per image, renders pass it (C++ copy). Now also: the layer's root carries `localKey = net.layerKey(version, w, h, mode)` and a render with an unchanged key returns the old node (`react.findOldChildByLocalKey`, the base construction menu's cache, construction.tl:3031-3044): no ImageView, no copy, nothing re-laid out. S/L still makes a new node (key has the size), but from the userdata. |
| `net_list` | 14 calls, avg 2.4, max 11.2 ms | Both street-system map calls **and** the flatten (pairs over node -> edges, building a list and a `hint` table of every edge, both grown by rehash) ran in one frame. Offline the flatten alone is 0.9 ms at 4k edges and 7.7 ms at 50k (Lua 5.4), plus the engine calls and the GC they trigger. | Three engine calls in three frames (`list_s`, `list_t`, `list_b`, each the only work of its frame). The returned maps are walked in 256-entry steps straight into the caches' seen stamps (`net.flattenStep`, max step 0.04 ms offline at 50k), so no per-scan list/hint tables of every id. Scans back off when nothing changed: 5 -> 10 -> 20 -> 30 s (cap `BACKOFF_MAX_SECONDS`), reset by any change, toggle-on or re-showing the window. No cheaper change signal exists: system.d.tl has no network or building revision, and town revisions don't move with building turnover (2026-10-08 review). |
| `net_encode` | 192 calls, avg 0.37, max 6.5 ms | Steps were 4096 px each (fine). The max is the growth of the empty encode table on a cold start (Lua doubles the array part; the last doubling copies 0.26-0.5 M entries in one step) or a GC step. Every update re-encoded the whole image (25 ms over ~60 frames in game) although one edge changes a few rows. | The grid flags changed bands of 8 rows (`grid.dirty`, set by drawPolyline/fillRect from the item's row range). With the kept buffer (userdata hand-off) an update rewrites only those bands; a fresh buffer, a palette switch or the table fallback encode all bands. `encodeRows` keeps the colour bytes in locals and tests the empty layer first (same bytes, golden test). The cold-start growth spike remains: inherent to building one 1 M-entry table in Lua 5.2; once per cold start (the 60 s park keeps the state). |
| `net_read` | 1331 calls, avg 0.05, max 6.2 ms | 16 `getComponent` reads are ~50 us; a 6 ms call is a GC step landing in it. Garbage sources: `drawPolyline` made a closure per drawn item (~330 bytes: 1.3 MB per first build at 4k edges, 16 MB at 50k, and again on removal), a new `items` table per chunk, the per-scan list/hint tables. | No closure (plot inlined into the loop), the chunk table is reused, no per-scan id tables. Raster garbage offline: 16.4 MB -> 0 KB for 50k edges. |
| `net_raster` | 1345 calls, avg 0.02 | fine | ~20 % faster (no closure); remove chunk 64 -> 16 items (a long edge is a few hundred pixels). |
| `net_diff` | 311 calls, avg 0.03 | fine (the diff over the flattened list) | Now the flatten + sweep steps (`net_flatten`, `net_sweep` inside). |
| `net_handoff` | (round 3) 7.9-8.2 ms per image in game (2026-10-10), every image change | One `ud.data = out` per image: the engine converts the 1 M-entry table (the same conversion `net_render` paid per render before). One engine call, can't be sliced. | Round 4: a frame of its own. 2026-10-10: **strips** (below): only changed 64-row strips are handed off, one per frame (~1 ms each at 512 px wide). |
| `cam_read` max 16.2 (1 of 1509), `rev_read` max 4.1 | | Not the network layer. Single outliers like the rare 20-40 ms slow lines; GC pauses of the shared GUI Lua state (the round-3 garbage cuts help all sections). | none |

Also seen: `preview_render` runs on every Content render too (0.9 ms avg, the MapPreviewComp params). Not changed
here; the same localKey cache could apply if it shows up.

### What changed (code)

- `content/minimap/minimap_netscan.tl` (new, pure): the scheduler moved out of the GUI script with the engine reads,
  hand-off, logging and SQPERF injected (`SquareMinimapNetIo`), so the whole pass is tested offline. Phases: `list_s`,
  `flat_s`, `list_t`, `flat_t`, `sweep_e`, `list_b`, `flat_b`, `sweep_b`, `remove_e`, `remove_b`, `read_e`, `read_b`,
  `encode`, `handoff`. `run()` checks the clock after every step; list calls and the hand-off only start a frame.
- `content/minimap/minimap_net.tl`: `flattenStep` / `sweepStep` replace `newDiff` / `diffStep`; closure-free
  `drawPolyline`; dirty bands (`BAND_ROWS = 8`, `bandCount`, `encodeBand`); faster `encodeRows`; `nextScanSeconds`
  (back-off); `layerKey`; `recolorAction` knows `handoff`.
- `gui/minimap_hud.script.tl`: io for the scheduler (maps checked to be plain tables, else copied), memoised layer
  render, back-off reset on toggle-on / re-show.

### New SQPERF sections

- ctx `step`: `net_list_streets`, `net_list_tracks`, `net_list_buildings` (each engine call; `net_list` is now per
  call, 3 per scan), `net_flatten`, `net_sweep` (their sum stays `net_diff`), counts `net_bands` (bands encoded),
  `net_scan` (scans started), `net_scan_empty` (scans without any change). Kept: `net_read`, `net_raster`,
  `net_encode`, `net_handoff`, `net_grid`, counts `net_publish`, `net_recolor`, `net_on_cold`, `net_on_cached`.
- ctx `gui`: inside `net_render`: `net_render_img` (the ImageView node incl. makeUserdata's copy), `net_render_tree`
  (layout nodes), count `net_render_reused` (renders answered with the old node).

### Offline numbers (Lua 5.4 / lupa, scratch bench, synthetic network: 80 % short edges, 2 % long, curved)

| | before | after |
|---|---|---|
| raster 4k / 20k / 50k edges | 5.2 / 25.4 / 60.9 ms | 4.1 / 19.5 / 48.7 ms |
| raster garbage, 50k edges | 16.4 MB | 0 |
| full encode 512x512, warm buffer | 12.5 ms (step 0.22) | 7.6 ms (band 0.15) |
| full encode 512x512, cold (growing table) | 16.1 ms (max step 0.88) | 12.9 ms (max step 0.78) |
| update encode after a 1-edge change, 512x512 | full encode (12.5 ms, ~25 ms in game) | 0.2 ms (changed bands only) |
| flatten + diff, 50k edges | 11.7 ms, 7.7 ms of it unsliced in `net_list` | 11.5 ms in steps of max 0.04 ms |
| Hermite sampling | 1.07 us/edge | unchanged |

Output identity: `tests/square_better_minimap/test_net_golden.lua` checksums (polylines, grid, encoded bytes in both
palettes x both row orders, 512x256 and 512x512, 6-8k edges + 5-6k buildings with removals) were computed with the
pre-change code and pass unchanged; `test_net.lua` checks partial == full encodes; `test_netscan.lua` checks the
scheduler's image against a direct raster after first build, updates, removals and palette switches.

### In-game run 1 after round 4 (2026-10-10 07:14-07:15)

Desert save, 512x512 image, 3.9k edges / 3.2k buildings, `stdout.txt`. The run lasted ~25 s, so **no SQPERF summary
line was printed** (they come every 30 s); the "after" numbers below are from the `[Minimap] net` log lines (totals
per pass, not per-call SQPERF stats). The next run must last at least 3 minutes (TESTING.md "P6 perf run").

| Section | Baseline calls / avg / max (ms) | After (run 1: `net` log lines) |
|---|---|---|
| `net_render` (gui) | 23 / 6.6 / 8.4 | no SQPERF window |
| `net_render_img` / `net_render_tree` / `net_render_reused` | (new) | no SQPERF window |
| `preview_render` (gui) | ? / 0.9 / ? | |
| `overlay_render` (gui) | ? / 0.1 / ? | |
| first build (whole pass) | 0.2-0.5 s wall, 20-29 frames (round 2) | 405 ms wall over 27 frames |
| `net_list` | 14 / 2.4 / 11.2 | first build: list 1.7 ms total (3 calls, 3 frames) |
| `net_list_streets` / `_tracks` / `_buildings` | (new) | no SQPERF window |
| `net_flatten` / `net_sweep` | (new) | first build: flatten 2.2 ms total (sliced) |
| `net_diff` | 311 / 0.03 / ? | |
| `net_read` | 1331 / 0.05 / 6.2 | first build: read 24.4 ms total (sliced) |
| `net_raster` | 1345 / 0.02 / ? | first build: raster 7.7 ms total (sliced) |
| `net_encode` | 192 / 0.37 / 6.5 | first build: encode 16.7 ms total (64 bands, sliced); update after Net off/on: 20.8 ms (64 bands: the parked state had dropped the buffer) |
| `net_bands` (count) | (new) | 64 per first build / palette switch / update after a park |
| `net_handoff` | (round 3, new) | **8.2 ms** first (incl. the check), **7.9-8.2 ms** every later image (palette switch, an update with `buildings +1`), all in ONE frame -> strips |
| `net_scan` / `net_scan_empty` (counts) | (new) | no SQPERF window |
| `rev_read` | ? / 0.9 / 4.1 | |
| `cam_read` | 1509 / ? / 16.2 | |
| slow lines (`slow=`) in the run | net_list 21.2, net_encode 38.4, rev_read 21.9 (round 2) | |

Also confirmed in run 1: the toggle's cached path works (instant, no first build); a palette switch re-encodes only.

### Strips (2026-10-10)

Run 1 made the hand-off the largest single step: 7.9-8.2 ms in one frame for **every** image change, even an update
with one building. Goal: no frame step over ~4 ms, `net_render` under 2 ms.

- **Tiling.** The image is shown as horizontal strips of `net.STRIP_BANDS` = 8 bands = 64 grid rows (the last strip
  may be shorter), each its own `ImageView` with its own Lua buffer and its own params userdata (`net.stripCount`,
  `stripRange`, `encodeStripBand`). 512x512 = 8 strips of 128 KiB. **Why 64 rows:** the hand-off cost is linear in
  bytes (8.0-8.2 ms per 1 MiB), so a 512 x 64 strip is ~1.0 ms, under the ~1.5 ms target with room for the per-call
  overhead; 32 rows (16 strips) would halve that but double the nodes and the frames a full publish takes (16), with
  every frame already well under 4 ms at 64. A fixed row count (not a fixed strip count) bounds the per-strip cost
  for every image shape (the long side is always 512, so a strip is at most 512 x 64).
- **Only changed strips.** The grid's dirty bands map to strips (`net.stripDirty`); an encode touches only strips with
  a changed band (only those bands when the strip's buffer is kept) and hands off only those strips, **one per
  frame** (`handoff` phase, `isHeavy`: the only work of its frame). A 1-building update = 1 band + 1 hand-off.
- **Atomic swap.** A hand-off fills a staged userdata (`st.staged[s]`, two userdata per strip alternating:
  `st.spareParams`), the shown one is not touched. After the last changed strip, `io.publish` swaps every staged
  strip into a new image version at once and re-renders: the picture never shows a half-new set of strips (even a
  node rebuilt mid-hand-off, e.g. on S/L, gets the old bytes). A failed hand-off publishes nothing; its strips stay
  `pending` and go out with the next pass.
- **Row flip per strip.** Every ImageView draws its first data row at its bottom, so each strip's buffer is its own
  rows bottom-up (`encodeStripRows`); strip 1 is the top of the picture. The whole flipped image = the strip buffers
  joined last strip first (unflipped: first strip first). Tested byte for byte against `encodeRows`.
- **Placement.** Strip rows r0..r1-1 of an image H rows high go at top = round(r0 * h / H), height =
  round(r1 * h / H) - top in a picture h UI px high (`net.stripPlacement`), through the existing full-size padded
  layer (`layerAt`, mouse-transparent Component). Strips tile the picture with no gap or overlap; a seam sits at most
  0.5 UI px from its exact position (each strip is stretched on its own, so a seam may show a 1 px rounding step only
  where h/H is not whole; at 512 rows into 360/560/720 px that is sub-pixel scaling anyway).
- **Node reuse.** Each strip is a `MinimapNetStrip` recipe whose root has `localKey = net.stripKey(s, stripVersion,
  w, h, mode)` and returns `react.findOldChildByLocalKey(key)` when found: the same root-level pattern as before (and
  as construction.tl), per strip. Its layer child key also carries the strip version, so a changed strip gets a new
  node (created with its data, never updated in place) and the others keep theirs. The layer root itself is no
  longer cached (its key has only the size): it builds ~4 small layout nodes per strip per Content render.
- **Encode buffer after Net off/on (decision).** Parking still drops the Lua buffers (~1 M values, ~16 MB as Lua
  values) and keeps only the engine-side copies; keeping 16 MB of Lua for up to 60 s while the layer is off was the
  wrong trade. With strips the cost of that drop is now small: after the re-enable only the strips that change are
  encoded again, **whole, into a new buffer** (8 bands, ~2 ms sliced, plus one ~1 ms hand-off), and every other
  strip keeps showing its engine copy without any buffer until it changes. Run 1's 20.8 ms / 64-band re-encode for
  `buildings +1` after an off/on becomes 8 bands + 1 hand-off. A fresh strip buffer also grows from empty only to
  128 Ki entries (the old cold-start growth spike copied up to 0.5 M entries in one step).
- **Expected per frame (512x512):** encode frames <= the 2 ms budget + one band (~0.26 ms in game); a hand-off frame
  ~1.0 ms (+~0.2 ms for the one-time check on the first strip); the publish frame's render builds only the changed
  strips' ImageViews (a C++ copy of 128 KiB each). Full publishes (first build, palette switch) take 8 hand-off
  frames (~130 ms at 60 fps) instead of one 8 ms frame.
- **SQPERF:** ctx `step`: `net_handoff` is now per strip (n = strips handed), new count `net_strips_handed`. Ctx
  `gui`: new `net_render_strip` (one strip recipe call), counts `net_render_reused` (strips answered with the old
  node; was per layer) and `net_render_built` (strips built); `net_render_img` now times one strip's ImageView,
  `net_render_tree` the layer's layout nodes. The `net` log lines add the strips handed per pass.

Tests: `test_net.lua` (strip geometry, strips joined == full image in both row orders incl. a short last strip, the
per-strip flip, changed-band-only re-encode per strip == fresh, placement tiles for 8 h/H pairs, stripKey,
calibration in a strip) and `test_netscan.lua` (first build hands off 4 strips one per frame with the publish in the
last frame; a 1-strip update hands off only that strip and the other strips keep their object/version; the version
changes only after the last hand-off; a failed hand-off publishes nothing and the pending strips go out next scan;
after a park only the changed strip is re-encoded whole; nothing changed = no hand-off; unflipped order).

### In-game run 2 (fill in)

Same save, steps in TESTING.md "P6 perf run" (**at least 3 minutes**: SQPERF summaries print every 30 s).

| Section | Run 1 | Run 2 (calls / avg / max) |
|---|---|---|
| `net_handoff` (per strip now) | 7.9-8.2 ms per image | 118 / 1.00 / 1.1 ms |
| `net_strips_handed` / `net_publish` (counts) | (new) | 117 / 16 (14 palette switches x 8 strips dominate) |
| `net_render` / `net_render_strip` / `net_render_img` (gui) | baseline 23 / 6.6 / 8.4 ms | 54 / 0.17 / 0.9; 424 / 0.01 / 0.1; 267 / 0.01 / 0.1 |
| `net_render_reused` / `net_render_built` (counts) | | 157 / 267 (reuse works) |
| `net_encode`, `net_bands` | baseline 192 / 0.37 / 6.5 ms | 965 / 0.17 / **10.1 ms** (see below); 963 bands |
| `net_list_*`, `net_flatten`, `net_sweep`, `net_read`, `net_raster` | baseline net_list 2.4 / 11.2 ms, read max 6.2 | streets 0.98 / 1.2, tracks 0.71 / 0.9, buildings 0.23 / 0.3; flatten max 0.1; sweep 0.0; read max 0.2; raster max 1.6 |
| `net_scan` / `net_scan_empty` | | 11 / 7 |
| `slow=` lines | GC-like 19-38 ms | none |

Run 2: autosave of "New Game - desert", 2026-10-10 07:29-07:31Z, 3.9k edges / 3.2k buildings, 120 s of SQPERF windows,
many Net / Hi-vis / S-L toggles. Every goal met except `net_encode` max 10.1 ms, in the 30 s window with Net off/on
cycles: the encodes right after a cached re-enable took 21.1 and 36.7 ms per pass (6.7 ms with warm buffers), because
parking dropped the ~16 MB of strip encode buffers and the next encodes built fresh 128K-entry tables while the GC swept
the old ones. Fix (2026-10-10): netPark keeps the encode buffers; they are freed with the other caches after 60 s off.
The same window had the only other spike (`overlay_render` max 10.3 ms, avg 0.15), likely the same GC pressure.
Not yet re-measured.

Run 3 (desert, 07:32-07:34Z, still the buffer-dropping build): `net_encode` max 1.1 ms; `net_handoff` 1.0 / 1.1 ms per
strip; `net_render` 0.20 / 0.9 ms; reused 136 vs built 96 strips; updates while building re-encoded 2-15 bands and
handed off 1-3 strips. Engine list calls peaked at 3.5 (streets), 4.7 (tracks), 4.4 ms (buildings) while building, vs
1.2 ms in run 2; unsliceable, one call per frame, every 5-30 s. Pre-existing outliers: `cam_read` 7.1, `rev_read` 4.9,
`preview_render` 4.1 ms (one each).

Run 4 (sub-arctic, 256x512 image, 07:48Z, buffers kept while parked; ~30 s, no SQPERF window): Net off logs "encode
buffers kept"; on again = cached image, first update 2 bands / 2 strips (0.1 ms encode, 1.1 ms hand-off); Hi-vis after
a re-enable 3.4-3.7 ms over 10 frames (warm; was 18-37 ms with dropped buffers); hand-off 0.5 ms per strip. A Hi-vis
switch during an update encodes one strip twice (66 bands / 9 hand-offs), harmless.

### What the in-game run must confirm

- `net_render_reused` > 0 and `net_render` n close to (image versions + S/L changes + mounts), max well under 2 ms
  with the userdata hand-off. If `findOldChildByLocalKey` didn't apply, `net_render_reused` stays 0 and `net_render_img`
  shows the copy per render.
- The picture stays on screen through Ind/Hi-vis/S-L toggles (a returned old node must still draw), and updates still
  appear (a new version builds a new node).
- `net_list_*` per call and `net_handoff` max: with strips ~1 ms per call at 512 px wide; `net_strips_handed` per
  update ~1 (8 on the first build and palette switches).
- No seam visible between strips (a 1 px line or a step in a road crossing a strip edge at y = 64, 128, ... image rows),
  and no half-old picture during an update (all changed strips switch together).
- `net_encode` n per update is small (a few bands); `net_bands` per update ~1-10, every band (64 for 512x512) only on
  the first image and palette switches.
- `net_scan_empty` grows on a quiet map and the `update` lines say "next scan in 10/20/30 s".
