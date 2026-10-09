# Performance review (2026-10-08, Washington)

Washington (`square_names_us_washington`) was reviewed, verified in game (2026-10-08: 5 Road Stops and 2 rail stations
renamed in Seattle, no errors), then every state was regenerated at revision 2. Changes are in the shared templates.

## Changes (templates/state_names, tools/gen_state_mod.py)

| # | Where | Before | After |
|---|-------|--------|-------|
| P1 | `rename.script.lua` `townGroups` | `getTown2StationsMap()[town]`, which builds the station map for every town on each Road Stop rename | `stationSystem.getStations(town)`, which returns one town's list (the map stays as a fallback) |
| P2 | `rename.script.lua` `collect` | Every player build with nothing removed ran `getComponent(CONSTRUCTION)` (in a pcall closure) on each result entity: every new edge and node of a track or road drag | Skips the scan when the proposal adds no constructions (`toAdd_native:size()`, then `#toAdd`; unreadable means scan as before). Same signal the base achievements script uses for station builds |
| P3 | `rename.script.lua` `doHandleEvent` | `isMapEditor()` → `getModParams()` (a copy of every mod's params) on every build | Called only after the build turned out to contain a stop or station |
| P4 | `rename.script.lua` `carriedOver` | Read `new2oldEdgeObjects` and walked all of `old2newEdgeObjects` once per Road Stop in the proposal: O(stops × map) conversions on a road upgrade | Both maps are read once per build, and old2new becomes a set (`edgeObjectMaps`) |
| P5 | `rename.script.lua` `doUpdate` | `state:get()` on every frame | Once per `os.time()` second. Entries only become due when the second ticks over, so renames happen just as soon as before |
| P6 | `sn_logic.lua` `addUsed` / `baseName` | Normalized each name twice (once for exact, again inside baseName); the tail-word strings were rebuilt in the loop | `baseOfNormalized(n)` plus precomputed `TAILS`. `newUsed` over 3000 names: 11.6 → 7.8 ms (lupa 5.4) |
| G1 | `tools/gen_state_mod.py` | Regenerating deleted `content/<modId>_presence.lua` (not rendered, so treated as stale) | Rendered from `tools/new_mod.py` `PRESENCE_STUB`. The text is identical, so the other states don't change |

New tests in `templates/state_names/tests/test_rename.lua` ("perf: …", 5 tests) cover P1, P2 (with its fallback), P3 and P5.
The fake world now has `getStations`, and `build()` fills `toAdd` with one entry per construction.

Not changed (measured, not worth it): `sampleTowns` takes about 30 ms for 250 towns, once per new game. `streetsFn`
shuffles the generic list per call, a few ms per load in total.

## In-game check (done 2026-10-08 on Washington rev 2)

- P2: building a new train station, bus station, airport or harbour still gets renamed. This relies on
  `toAdd_native:size() > 0` for construction builds.
- P1: `getStations(town)` returns the same stations as the map, so a second Road Stop in a town doesn't reuse a
  street name.

## Rollout to the other states

Running `make state-mods ARGS=--check` before rollout lists 3 stale files per state: `rename.script.lua`,
`sn_logic.lua` and `tests/<modId>/test_rename.lua`.

```
make state-mods
make state-mods ARGS=--check
make check && make test        # or per state: MOD=mods/square_names_us_<state>
```

Every state was bumped to revision 2 (user decision, 2026-10-08) with the changelog item
"Faster: less work on every build and every frame, and a quicker street name check in big towns."

- [x] us_washington (rev 2)
- [x] us_alaska (rev 2)
- [x] us_arizona (rev 2)
- [x] us_california (rev 2)
- [x] us_colorado (rev 2)
- [x] us_florida (rev 2)
- [x] us_hawaii (rev 2)
- [x] us_minnesota (rev 2)
- [x] us_new_mexico (rev 2)
- [x] us_new_york (rev 2)
- [x] us_oregon (rev 2)
- [x] us_pennsylvania (rev 2)
- [x] us_texas (rev 2)
