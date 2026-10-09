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
