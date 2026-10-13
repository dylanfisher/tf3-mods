# square_roundabouts: performance review

Status: done 2026-10-08, nothing changed. Covers the four entries of revision 3; the highway entries (revision 4) were not reviewed here.

## 2026-10-08

Verdict: **nothing worth changing.** No shipped code was touched; revision stays 3.

### Where the mod spends time

The mod has no game script, GUI script, runFn, timer or event handler (no `runFn`, `guiUpdate`,
`handleEvent`, `api.engine`, `api.cmd` or `game.interface` anywhere). Its only runtime code is the
four construction `updateFn`s (Better Roundabouts, Magic Roundabout, Channelized Junction,
Roundabout Interchange). They are pure Lua and run when the player opens the entry or changes a
param while placing (and possibly once per placed construction when a save loads, for the island
subconstruction). Nothing runs per frame or per tick.

### Measurements (offline harness, Lua 5.4 via lupa, this Mac)

| What | Result |
|---|---|
| Better Roundabouts updateFn (geometry + result), 3000 random param sets | mean 1.1 ms, p50 0.5 ms, p90 1.9 ms |
| Same, worst configs re-timed (GC collected first, best of 5) | worst 5.0 ms (tram line through a 3-arm Y ring with tram tracks); single-run peaks up to ~20 ms were GC pauses |
| Default params | 0.3 ms |
| Magic Roundabout, 500 random sets | mean 0.7 ms |
| Channelized Junction, 500 random sets | mean 1.3 ms |
| Roundabout Interchange, 500 random sets | mean 2.0 ms |
| `square_roundabouts_tuning.lua` (70 KB generated table) raw load | 0.8 ms once per Lua state |

Where the worst builds spend their time: `geom.choosePlan` trying up to ~6 radii, each
`geom.plan` → `ringFree` → `kerbCut` / `arcLength` (bisection over ellipse points), and
`geom.islands` → `S.fits` / `S.distToBoundary` / `S.boxFrom` for the split centre island.

### Examined and deliberately not changed

- Radius search in `choosePlan` (several full `plan()` calls): a few ms at worst, once per param
  click. Memoising or caching across calls would add state to a pure updateFn for no visible gain.
- `kerbCut` / `solveSide` bisection loops (60 / 20 iterations): accuracy is what the engine-tuned
  table (`square_roundabouts_tuning.lua`) was searched against; fewer iterations would risk
  changing accepted layouts and would need the full SQRB_FULL sweep plus new engine probes.
- Island `fits` / `boxFrom` sampling: ~1-3 ms only when a through road splits an island with trees
  or a fountain.
- Tuning table load: under 1 ms.
- Per-save-load cost: even at ~1-5 ms per placed construction, a map with 100 of them costs well
  under half a second of load time, and only if the engine re-runs updateFn on load at all.

### In-game check list

None needed (no code changed). Optional: with many Better Roundabouts placed, clicking params in
the construction menu should feel instant (each click is one updateFn, a few ms at most).
