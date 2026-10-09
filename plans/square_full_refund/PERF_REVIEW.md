# Performance review (2026-10-08, revision 1 → 2)

All changes are in `content/refund/refund.script.tl`. The logic module, the saved state format and the behaviour are unchanged.

## Changes

| # | Where | Before | After | Gain |
|---|-------|--------|-------|------|
| P1 | `doUpdate` | `state:get()` on every frame. That converts the whole ledger (up to 400 entries, each with a 6-number `g` table). The ledger is pruned only on the next build event, so after a long road drag it can stay full indefinitely | A Lua-state-local `updateWork` flag is set by `onPost` (pending `await`) and `settle` (payout). `update` reads the state only when the flag is set, plus once per `os.time()` second as a safety net. The flag starts as `true`, so a payout saved in the game is booked on the first frame after a load | A pure-Lua deep copy of a full ledger as a proxy takes **0.58 ms** (lupa). With the change, an idle frame does about 0 state reads instead of one. Bookings are still sent on the first frame after the build event |
| P2 | `doUpdate`, unsubscribed branch | In the map editor (never subscribed), `isMapEditor()` → `getModParams()` copied every mod's params on every frame | Checked at most once per `os.time()` second while in the editor. Nothing changes outside the editor, where the script subscribes on the first frame | Removes a per-frame params copy in the editor |
| P3 | `takeRemoved`, `record` | With `PROBE = false`, every build and bulldoze still built the probe strings: `idList`, `edgeList` (an extra `edgeKey` `string.format` per segment) and the share list | That string building is behind `if PROBE` | Small. Fewer allocations per build event |

Why the flag doesn't need a cached state: the two pieces of work update does (`pending.await` re-measure, `payout` booking) only ever come from a build event in the same script, or from a saved game (covered because the flag starts as `true`). If the engine ever ran events and update in different Lua states, the once-per-second safety net would still book the credit, at most about 1 s later.

Tests: 4 new `perf:` tests in `tests/square_full_refund/test_script.lua` (idle frames, payout in a loaded state, booking right after idle frames, map editor). The idle-frame and map-editor tests fail on the old script.

## Examined, not changed

- `windowMs()` → `getModParams()` on every player build's pre event. This happens once per player action (a few per second at most while dragging). Caching it across events needs proof of the Lua state's lifetime across loads, because params can differ per load. plan.md made a deliberate "no cache" decision. Not worth the risk.
- `logic.takeEdges`: O(edges × ledger), at most about 10 × 400 `sameEdge` calls per road build, well under 1 ms. `logic.prune`/`take` allocate a new list per event: O(400), negligible.
- `readShape` copies `p[3]`: one short int list per event.
- `hasEventSubscriptions()` per frame: a single native bool call.

## In-game check

- [ ] Build a depot, bulldoze it right away: the balance returns to the pre-build value, and the credit appears at once (no 1 s delay).
- [ ] Drag a road, bulldoze a segment: the credit still arrives.
- [ ] Save right after a bulldoze, then reload: no error. A pending payout, if any, is booked.
- [ ] Open the map editor with the mod active: no warnings in stdout.
