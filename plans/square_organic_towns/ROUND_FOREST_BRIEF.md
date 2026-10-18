Status: done 2026-10-13 (R1-R7; PLAN.md 6.3 "Forest / gaps / bridges round", NEXT_PHASE_BRIEF 35); tested in run
`2026-10-13_2113_sqot-dev` (results HISTORY.md); follow-up NEXT_PHASE_BRIEF 36.

# Organic Towns: forest, gaps, empty streets, motifs, bridges, industry (round brief, 2026-10-13)

Source: run `2026-10-13_1945_sqot-dev`, analysed read-only (main-session summary below), the user's notes, and the
user's in-game bridge test. Implement in phases, one test at the end (the user's standing workflow). Rules:
- CLAUDE.md, including the loop-cap rule.
- Crash rule: every new node gets a BASE_NODE_CONFIG.
- Don't impact existing saves.
- 13 languages for new user-visible strings (the DEV mod is exempt).
- Run only this mod's tests (plus the dev mod's if touched).
- No commits, no `make modio`.

Each phase updates PLAN.md / NEXT_PHASE_BRIEF.md / TESTING.md as it lands.

User's words for this round:
- "building around forests is really cool, let's keep pushing this"
- "environmental cues continue to be the most interesting thing about this mod"
- "overall town growth starting to look very organic"
- On Billingham's suburbs around the forest: "if we build a road between a forest take into account the size of the houses that will pop up there, sometimes removing the forests. obviously our towns need to grow to cover some trees, but we should be aware"
- "if a street is in between a forest and close enough to trees, we block building for part of the road to ensure no houses take over (but game should be able to extend past and continue the road). we should use that sparingly so there's still some houses built in forests"
- "a low bridge does cut ship lane. this is ok IF there's no active path through it. can we check that? if there is, we should either not build the bridge or figure out if we can build it high enough... prefer narrow river stretches that aren't navigable"
- Alsager: "an industrial outcropping across the bridge that is cool, but also has lots of industrial mixed in the rest of the town"
- On towns that grow against each other: the gap proposal (stop short of the halfway line) was offered and is part of this round.

## Phase R1: forest by plot depth (ot_forest, ot_select, ot_plan, dose)
Run evidence:
- `FO.pen` samples only the street centreline (50 m cells).
- `FO.edge` gives a 0.8x cost bonus (`EDGE_GAIN`) to a street whose next cell is forest. That steers streets whose forest-side lots overlap the trees; lots reach about 36-40 m from the centreline (`ot_style.lua:18`: 4 x 8 m).
- Dose `openSide` tests one point 20 m out (`FILL_OFFSET`).
- The grid is re-read only every `RENEW_S` = 1200 s.
- Once relaxed, increments of 1-5 edges come out `forestCut=1.00`: `forestOk` checks `CUT_FILL` against `maxEdges`, not the actual edge count.
- Stride bias in `coverOf`: light = max(12, 1.5·stride/0.25 ha), dense = 2·light. At stride 5 almost nothing reads dense: Redruth / Southminster, visibly wooded, read `none`.

Changes:
1. Measure each piece over a corridor: centreline plus +-20 m and +-36 m on each side. Keep the per-side cover.
2. `EDGE_GAIN` only when one side is open to lot depth and the forest starts beyond about 40 m on the other side. Point dose fills and side streets to the open side.
3. Cap the wooded length per increment in metres against the actual edge count.
   - Add a per-town, per-decade clearing budget (forest cells under lots), so towns still cover some trees on purpose.
   - Log `forestLot=` and `forestBudget=`.
4. Re-read the forest grid after N builds or M edges, sliced.
5. Fix the stride bias: keep the 12/36 thresholds on density corrected for stride, or read more trees.
6. Add `slices=` to the PLAN line of plans that end empty (`ot_driver.lua` ~1880).
7. Spread the CHECK `us` (up to 80 ms in one frame, Billingham) over slices, or cache its reads.

## Phase R2: "forest lane" (houses held off a stretch, used sparingly)
Where a planned street passes through forest with trees within lot depth on BOTH sides:
- build that stretch as a country template (era-matched `country_old_small` / `country_new_small`), locked;
- the parts before and after stay town streets, so the town can extend past it.

Findings to rely on (docs/findings/towns.md): country templates get no houses (verified for highway_new_*; check the country_* evidence); script streets get `roadDevelopmentLocked`; the game builds town streets off country roads.

Use it sparingly:
- about 1 in 3 eligible crossings, seeded;
- more in towns whose forest mode is hug, fewer in towns that build through the forest and in later eras;
- a cap per town.

Elsewhere houses still go into the woods. Log `FORESTLANE town= edge= len= why=`.

One-sided variant (a street along the forest edge): the base `barrier_a` / `barrier_b` edge decorations have `preventParcels = true` and a side flag (`BaseEdge.edgeDecorations`). They are noise barriers, so use them only if R1's placement can't do it, behind a constant, default off.

DEV showcase: add a forest-lane case to verify in game:
- no lots on the lane;
- the town keeps building past it.

## Phase R3: gaps between towns
- New mod streets stop 150-300 m short of the halfway line to a neighbouring town's centre (Voronoi between centres; use `E.closestTown` or the centres list).
- Twins (`SH.TWIN_NEAR` 1800 m, river-bank pairs) are exempt, but they meet along their main road (a ribbon-like link), not as a mass.
- Log held pieces as `gapHeld=` on PLAN.
- Never build streets that would belong to another town (closestTown != this town).

## Phase R4: empty streets
Unhoused geometric stubs and loops in Kirkham, Fleetwood, Syston and Ormskirk; Rushden's bridgehead has `houses=2`; Hitchin is sparse.
- Fewer streets ahead of the houses for those cases.
- Retire or stop extending dead ends that stay empty after K checks.
- No rectangular empty loops in organic styles.
- Check why Tisbury / Stotfold, logged `linear`, look round.

## Phase R5: motifs that build
- hill_climb: picked 6 times, 5 came out `none:flat/short`.
- switchbacks: 3 of 4 `noBend`.
- crossroads_hamlet: always `waiting`.
- ribbon_village: `noRoom` / 0 m.

Fix eligibility so a pick matches what the build step can do (same terrain read, same thresholds), or let the build fall back to the next eligible kind.

Peninsula detection: Alsager, visibly a peninsula, has `spit=-`. Widen the spit / peninsula read.

## Phase R6: bridges and ships (user-verified: a low bridge cuts a ship lane, docs/findings/roads.md)
1. Prefer narrow river stretches that aren't navigable. Research how to read navigability: the line manager's navigable-water layer, `api.engine` terrain or water-mesh queries (`.cache/game/api/tealdef`); `base/content/gui/line_vehicle_mgmt/line_util.tl` shows the layer.
2. Check for active ship paths. Ship lines are lines with water carriers; read each line's stops (harbours) and, if readable, the vehicles' paths. A crossing whose line would cut the water between two stops of one ship line, or a path a ship is using, is an active path. Then either:
   - build the deck high enough, as a constant clearance over the water level (about 10-12 m, unmeasured). The approaches at `MAX_GRADE` 0.08 get longer, so skip the crossing when they don't fit;
   - or don't build the bridge.

   Never build low over an active path. Log `BRIDGE ... ship=none|path|navigable deck= clearance=`.
3. Over navigable water with no active path, the user accepts a low bridge. Prefer a high deck when it fits, since a line may come later.

## Phase R7: industry mix (Alsager)
- The mod has no per-area zoning; the API offers town-wide capacities only (research 2026-10-13).
- The DEV SIMGROW keeps each town's starting share: Alsager starts at 34 % industrial and grows all three alike. Give SIMGROW a realistic split, mostly residential, per era.
- DEV probe: a separate industrial-heavy satellite town across a bridge, via `makeTownCreateCmd` with TownInfo `initialLandUseCapacities` such as {10,10,200}. Does it build only industry?

  Main mod later, only if the probe works.
- Optionally keep the dose fills off a town's industrial district centre (`getTownDistrictCenter`).

## Final test (one, after all phases)
TESTING.md section "Forest / gaps / bridges round test", together with the Landscape names / stop names test:
- a forest map;
- a river with one ship line through a town stretch;
- one station facing away from its town.
