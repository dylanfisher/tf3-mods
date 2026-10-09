# square_full_refund — plan

Goal: undo mistakes for free. Bulldozing something, or selling a vehicle, shortly after placing/buying it gives a full refund.

## Research (2026-10-07)

- Base game `base/content/base/mod.script.tl` `preRunFn` sets `baseConfig.costs` with
  `bulldozeRefundTimeOut = 60.0` and `bulldozeRefundFactor = .75`: bulldozing within the window already refunds 75%.
- Vehicle sale price is engine-side depreciation (`api.engine.util.vehicle.getDepreciatedValue`); no config knob.
- Money can be credited with `api.cmd.makeJournalBookAssetCmd(player, entry, pos)` (`JournalEntry.Type.OTHER`),
  as the campaign does in `urbangames_campaign_mission_08/content/mission/mission_story.tl:1016`.

## Phase 1 — bulldoze refund (config only)

- Scaffold `mods/square_full_refund` (name "Full Refund", tag fitting a gameplay/config mod).
- In `preRunFn` (runs after base mod's, so it can override): set `baseConfig.costs.bulldozeRefundFactor = 1.0`.
- Mod setting for the refund window (e.g. 60 s vanilla / 2 min / 5 min / 10 min), if TF3 mod params support it.
- Must not impact saves: severity None/None.
- Open questions to verify in game: is the timeout real or game seconds; does it cover streets/tracks as well as constructions.

## Phase 2 — vehicle refund (game script) — blocked

Blocked on in-game measurement: buy a vehicle, sell it immediately, note purchase vs. sale price.
If the loss is material: GS records price + time at buy; on a real sale (not replace) within the window,
credit `price - depreciatedValue` via a journal booking. Lazy init, track only vehicles bought after enabling.

## Phase 1 result (2026-10-07, in game)

Config override does NOT work on a loaded save. Log confirms preRunFn ran
(`bulldozeRefundFactor = 1, bulldozeRefundTimeOut = 120`), but a road depot costing $1,084,412
bulldozed immediately lost $271,106 = exactly 25%. Likely costs config is baked into the save at
game creation. Params are 0-based (picked "2 min" → refundWindow = 1 → 120 s).

## Phase 1b — script-based bulldoze refund (chosen by user)

Drop the config tweak (or keep as harmless). A game script records build cost + time for player
constructions/edges, and on bulldoze within the window credits the missing fraction
(cost * (1 - 0.75)) via `api.cmd.makeJournalBookAssetCmd`. Must work on existing saves.

### Phase 1b design (from research 2026-10-07)

- Engine game script (`.gs.lua` + `.script.tl`, template: square_problem_radar / square_quota_run), lazy
  `subscribeToEvent` in `update` for `onPreBuildProposal` / `onPostBuildProposal`; handle `id == "apply_command"`,
  param `{Proposal, ProposalData, {Entity}, playerInitiated}`; require playerInitiated.
- Post event with additions (`#toAdd > 0` or street `addedSegments`) → ledger[entity] = {cost, t} (split data.costs).
- Pre event with pure removal (`#toAdd == 0`, no addedSegments) → for ledger hits inside our window, owe cost.
  Measure what the engine actually paid by reading the player balance in pre and in post
  (`api.engine.util.finance.getPlayersBalance`); credit `owed - actualRefund` so it's correct whatever the
  engine's factor/clock. Fallback 25% if balance is unavailable (infinite money → skip).
- Book via `makeJournalBookAssetCmd`, positive amount, `time = -1`, try CONSTRUCTION/BULLDOZER, fallback OTHER.
- Rebuild/upgrade (toAdd and toRemove together) → drop ledger entries, no credit.
- Ship with verbose `log.message` probe lines (data.costs sign, p[3] for streets, balance deltas) for the first in-game test.

### Phase 1b status (2026-10-07): implemented, awaiting first in-game test

- `preRunFn` config override removed (`content/mod.script.tl` deleted, `preRunScript` dropped from mod.json).
- Game script: `content/refund/refund.gs.lua` → `refund.script.tl` (adapter, engine calls) + `refund_logic.tl`
  (pure ledger logic) + `refund_types.d.tl` (state/logic types, editor copy in `tealdef/`).
- Params in the GS: `api.engine.config.getModParams()["square_full_refund"].refundWindow`
  (`api/tealdef/api/engine.d.tl:1806-1807`; base reads `[""]` the same way in towns.script.tl:58,
  better_minimap reads its own in game). The param now has `"numbers": [60, 120, 300, 600]`
  (wiki modscripts.md "Mod Params": numbers are what scripts receive), so the raw value is the seconds.
  Fallback when a plain index arrives: 0-based (as preRunFn showed). Read on every apply_command, no cache.
  Note: wiki and community mods (zhenya_*, auto_line_namer) say values without `numbers` are 1-based,
  which contradicts the Phase 1 observation; the probe line `subscribed; refundWindow param raw=…` settles it.
- Event flow: post add/rebuild → ledger += p[3] entities (fallback: addedSegments via old2new) with an
  equal share of `data.costs`; pre pure removal → take hits within the window, store owed + balance in
  `state.pending` (fingerprint of the removed ids); matching post → credit `owed - max(0, balance delta)`;
  if the post shows no refund yet, re-measure on the next `update`. Rebuild pre → drop entries, no credit,
  new entities recorded with the rebuild's cost (needed because dragging a road off an existing one is a rebuild).
- Booking: `makeJournalBookAssetCmd`, positive, `time = -1`, CONSTRUCTION/BULLDOZER
  (`BOOK_AS_BULLDOZER` constant → OTHER). Window clock: `GAME_TIME.gameTime` (ms).
- Tests: `tests/square_full_refund/test_logic.lua`, `test_script.lua` (fake api, full event flow).
- To verify in game: balance is updated synchronously between pre and post; p[3] for streets/tracks;
  the Bulldozer line shows the credit; gameTime vs wall clock at 1x/4x; raw param value.
- Phase 2 (vehicle refund) unchanged: planned.

## In-game results 2026-10-08

- Constructions (road depot) work end to end: balance returns exactly to the pre-build value.
  Credit must be sent from `update`, never inside the build event (Engine assertion `!m_betweenChanges`).
  Pre/post of a removal are paired by counts; removed ids differ by post.
- Param arrives as 0-based index (`raw=1` for "2 min") even with `numbers` in mod.json.
- Game time does not advance while paused, so the window doesn't expire while paused. **User prefers this; keep it.**
- Roads: `#p3=0` and old2new yields nothing for street builds, so segments are never recorded.
  Bulldoze removals come one segment per proposal (`removedSegs=1`, ids like 18879, 22621) with
  `data.costs` = minus the engine refund (~75%). Needs a different key for edges (see Phase 1c).

## Phase 1c — roads and tracks

Key street/track segments by geometry instead of entity id: on post add/rebuild, for each
`addedSegments[i]` take its endpoint positions (from `addedNodes` for new negative node ids, else the
existing node's BASE_NODE position) → order-independent rounded key; cost share proportional to segment
length. On pre removal, removed segments still exist: read BASE_EDGE node0/node1 → BASE_NODE positions →
same key. Constructions keep the entity-id path.

### Phase 1c status (2026-10-08): implemented, awaiting in-game test

- **No id path for edges.** `ProposalData.old2new` is empty for streets in game; `entity2tn`
  (`api/tealdef/api/type.d.tl:2755`) is keyed by the proposal's placeholder ids and holds TransportNetwork
  components, not final ids (used that way in subscribed undo_tf3_test track_builder.script.tl:1900-1901);
  parallel_tracks_1 finds new edges via `streetSystem.getNodeTrackSegments(node0, node1)`, which needs real
  node ids (new nodes are negative). So segments are keyed by geometry.
- **Fields.** `Proposal.proposal : StreetProposal` with `addedSegments` / `removedSegments : {SegmentAndEntity}`
  and `addedNodes` / `removedNodes : {NodeAndEntity}` (type.d.tl:2511-2559). `SegmentAndEntity.comp :
  Engine.Component.BaseEdge` has `node0, node1, position0, position1, tangent0, tangent1`
  (api/tealdef/api/engine.d.tl:99-127); `BaseNode.position` (engine.d.tl:157-162). parallel_tracks_1 reads
  `seg.comp.position0/1` from `onPostBuildProposal` (parallel_tracks.script.lua:119-137).
- **Geometry per segment** (`refund.script.tl` segGeom): `comp.position0/1` → (pre only, live segment)
  `getComponent(entity, BASE_EDGE).position0/1` → node positions (`addedNodes[].comp.position` for new
  negative node ids, else `getComponent(node, BASE_NODE).position`). Length = max(chord, mean tangent length).
- **Key** (`refund_logic.tl` edgeKey): `"e:x0,y0,z0|x1,y1,z1"`, 0.1 m, endpoints sorted so it is
  order-independent. Entries store the canonical endpoints too (`g`) and matching uses a 0.5 m per-coordinate
  tolerance in either orientation (`sameEdge`), so rounding boundaries and float noise don't break a match.
  Construction entries keep `e` (entity id); edge entries have `k`/`g` and no `e`. Same state version (old
  saves' entries stay valid).
- **Cost split.** Post add: constructions in p[3] take the whole `data.costs` (their auto-built connecting
  street is part of the price and is removed with them, as the depot bulldoze showed); only when no
  construction id is known are the added segments recorded, split by length (remainder to the longest).
- **Rebuild.** Pre: matched entries (constructions by id, segments by geometry) are dropped without credit
  and their summed cost is kept in `state.carry`. Post: carry + `data.costs` (never < 0) is recorded on the
  new objects. So build → branch off → bulldoze everything refunds exactly what was paid in total; the
  credit can never exceed the paid total because every credit is `owed - engine refund`, clamped at 0.
  New entries get the rebuild's time (the window restarts at a rebuild).
- **Probe lines** now list edge keys, lengths and the geometry source (`src=comp|edge|nodes`) for added and
  removed segments, the shares recorded, the edge hit count on removal, and the carry on rebuild.
- Tests: 33 passing (3-segment street bulldozed one by one sums to the build cost, length split, node
  fallback with reversed orientation, rounding tolerance and 2 m miss, branch-off rebuild with carry,
  untracked rebuild, mixed construction + street, window expiry).
- **To confirm in the next in-game log:** `src=comp` on added segments in post (positions really filled in
  the applied proposal) and on removed segments in pre; the post-build key equals the pre-removal key for
  the same segment; whether the engine's per-segment refund ~ 75 % of our length share (if the engine prices
  segments very unevenly, e.g. bridges/slopes, single-segment credits are approximate but the street total
  is exact); what a branch-off rebuild removes/adds; tracks behave like streets.

## Release prep (2026-10-08)

Constructions and roads confirmed in game (balance returns exactly to the pre-build value, incl. branch-off).
Probe trace disabled (`PROBE = false` in refund.script.tl; warnings still log). Description and modinfo
fallback finalised; cover/branding entry from Phase 1 kept. Vehicles (Phase 2) still blocked on the
resale measurement.
