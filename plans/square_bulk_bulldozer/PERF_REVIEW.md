# Bulk Bulldozer: performance review (2026-10-08)

Scope: everything in `mods/square_bulk_bulldozer/content/bulk_bulldozer/`. The mod is GUI-only (no game
script, no saved state), so the hot paths are the action recipe's `onStep` (every frame while the tool is
open), brush samples (every 100 ms or every radius/4 of cursor travel), re-renders of the world layer
(on every cursor move > 0.25 m and every selection change) and the overlay rebuild (every selection change).

## Changes (revision 1 → 2)

| Where | Before | After | Gain |
|---|---|---|---|
| `bb_gather.tl` `gather.sample` (+ `edgeLight`/`edgeFull`, `constructionLight`/`constructionFull`) | Every entity in the octree query (radius **r + 100 m**) was described in full: `entityExists`, the main component, `PLAYER_OWNED`, `BASE_EDGE_STREET`, `getConstructionEntityForEdge`, 2× `getConstructionEntityForNode` for unowned streets, `SUBCONSTRUCTION`, station owner scan. Most of those entities are then dropped by the touch / origin test. | Two steps: the light step reads only what the test needs (`BASE_EDGE` geometry; `CONSTRUCTION` origin + counts, which also mark industries for the road protection). The full step runs only for entities the brush hits, before `sel.classify`. `describeEdge` / `describeConstruction` (used by the commit's hard-rule recheck) still return complete descriptors. | Measured with a fake api on a synthetic town (40 m street grid, a house every 20 m), engine reads per sample on a cold cache: **r = 20 m: 822 → 362 (−56 %)**, **r = 200 m: 5386 → 3690 (−31 %)**. Applies to every hover sample on new ground and after each 2 s hover-cache refresh, and to every stroke's first pass. |
| `bulk_bulldozer.script.tl` `buildOverlay` (+ `PieceCache`, `refPieces`); `bb_highlight.tl` `piecePlan` / `curveSegments` | The red / coral overlay (up to 1600 `EdgeRenderable` pieces, each ~7 `api.type.*.new` natives) was rebuilt **from scratch** on every selection change: every brush sample that added something while painting, and every hover change (every 100 ms while moving a big brush). | Pieces are cached per entity, per phase and per piece count, for the lifetime of the gather cache (a stroke, or a 2 s hover cache). A rebuild only makes pieces for new entities (or when the budget changes an edge's piece count); markers likewise. `hl.edgeSegments` is now `piecePlan` + `curveSegments` with identical output (existing tests unchanged). | Painting a stroke of N entities: piece construction drops from O(N) per sample to O(new) per sample (test: second stroke makes 2 new pieces instead of 6). Expected to remove the periodic hitch while painting / hovering a large selection; not measurable offline (native allocation cost). |

Behaviour is unchanged: classification only ever sees complete descriptors (test
`cost: results equal a full describe of every queried entity`, `... a light descriptor is completed when a
later sample touches it`). One deliberate difference: a station construction without its own `PLAYER_OWNED`
re-reads `CONSTRUCTION` in the full step (rare path) instead of keeping the component around; if that
re-read fails the owner stays −1, i.e. not selected (fail-safe direction). Overlay markers keep the terrain
height read when the marker was first made (constructions don't move while selected).

Tests added: `tests/square_bulk_bulldozer/test_gather_cost.lua` (read counts + equivalence, prints the
numbers above), one overlay-reuse test in `test_action.lua`.

## Examined, deliberately not changed

- `onStep` every frame: `publishIfChanged` builds the status text (a few `string.format` + clip) and compares
  a key; a few µs per frame. Not worth a version-key cache.
- `onStep` cursor follow: `hasTerrainPosition` / `getTerrainPosition` each frame are needed for the ring.
- World-layer re-render on every cursor move: 48 `getHeightAt` + 48 arc edges for the ring, a copy of the
  highlighted list (≤ 400) and the bag of overlay pieces. Inherent to a cursor-following ring; the overlay
  itself is cached. The engine may re-marshal the whole `EdgeRenderable` (ring + up to 1600 overlay pieces)
  each render; only one EdgeRenderable per recipe is allowed (engine assert), so the ring can't be split off
  safely. Watch in game (below).
- Hover sample bookkeeping (`newSelection` → `gather.context()` 2 native calls, `sel.describe` twice for the
  change test): per 100 ms, negligible.
- `entityExists` before every `getComponent`: kept as a safety check (behaviour of `getComponent` on a dead
  entity unverified).
- Cost preview (`commit.preview`, `makeProposalData` over the whole stroke) is already throttled to
  `PREVIEW_INTERVAL` = 0.25 s and only when the stroke grew; logged when over 20 ms.
- Mouse event logging (one line per non-Moved event, Moved summarised every 0.5 s): debug output, not hot.
- Wide construction query (r + 100 m) is needed to find industries whose access roads must be protected;
  only its per-entity cost was reduced.

## In-game check list

- [ ] Hover a 200 m brush across the densest city: `slow sample` lines (> 4 ms) are fewer / lower than before;
      no visible stutter every ~100 ms while moving.
- [ ] Paint a long stroke up to the 400 cap over a town with a 100-200 m brush: the red overlay grows
      smoothly, no hitch per sample; release → overlay turns to the selection colour once.
- [ ] Selection results unchanged: industry access roads still `Skipped: industry`, other players' objects
      `other player`, station roads `part of a construction`, your stations selected with Stations & depots on.
- [ ] Bulldoze: the commit log line counts and costs look as before.
