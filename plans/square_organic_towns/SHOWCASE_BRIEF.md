# Showcase test (dev tools): brief for the next agent (2026-10-11)

User request: a dev-tools test for a **Blank Slate** map (mods/square_blank_slate: one flat island at 5 m, gentle
coast, sea all round, nothing else) that spawns one town per supported style, grows each automatically through
enough increments for a large build-out, then lets the user screenshot each and give feedback. Start only after
the organic-geometry fix (curved styles refused with Construction_Not_Possible) is in, it touches the same files.

## Requirements
- **One button "Showcase: build all"** in the dev window (mods/square_organic_towns_dev), fully automatic:
  1. Spawn one town per style in ot_style.IDS (NA_GRID, NA_SUBURB, EU_ORGANIC, EU_EXTENSION, MED_HILL,
     MED_ENSANCHE, JP_DENSE, NORDIC, SUPERBLOCK), with `makeTownCreateCmd` (works in a running game, findings
     "create town": one at a time, `createTowns` returns all towns in toRemove — ignore it; resultEntities empty,
     find the new town by diffing the town list). Lay them out on a grid with ~2.5 km spacing so they never meet,
     away from the coast, except styles whose axis follows a shore (place one or two near the coast if the style
     uses shore alignment, and log it).
  2. Per town: `initialMajorStreetAngle`/`majorStreetAngle` in TownInfo suited to the style (0 for grids, larger
     for organic), so the seed core already matches. Rename each town to its style label
     (`makeEntitySetNameCmd`), e.g. "EU organic".
  3. Grow each town through N increments (picker: 10 / 20 / 40), round-robin, each increment followed by forced
     growth so houses fill, with the main driver paused. Style forced per town (dev style override). Stop a town
     after K consecutive refusals; log why. Progress shown in the window (town, step, built/refused).
  4. When done: a **"Next town" / "Previous town"** camera button that flies the camera to each showcase town
     at a fixed overview height/angle (consistent screenshots), showing its label, step count, buildings, edges,
     refusals in the window. Plus "Top-down view" toggle if a camera API allows it.
- **Irregular growth:** real towns don't grow as even rings. Make the planner pick growth directions unevenly for
  styles where that's realistic: ribbon growth along arterials/main roads (profile `ribbon`, `lead`), sector
  preference seeded per town, toward the coast/station, leapfrog patches for suburbs. Grids may grow more evenly
  but still favour arterials. Verify offline with ot_core.simulate + SVG previews (centroid drift, sector spread
  metrics) and add tests per style.
- **Extra screenshot tests in the same run** (separate row of towns, labelled):
  - Probe C: vanilla towns (no mod growth) with initialMajorStreetAngle 0 / 15 / 45 / 90, grown only by the
    game (forced size), to see what the angle does and whether a mod setting could style starting towns.
  - A vanilla control town per row (no mod streets, same forced growth) for comparison.
  - Era: one NA grid town with old templates vs new templates if the start year allows.
- Log everything with `[SQOT_DEV] SHOWCASE ...` lines (per town: style, position, angle, steps, edges, buildings,
  refusals with reasons, cost) so the log alone tells the story; final summary line.
- Cost: builds currently charge the player (~500k per increment); Blank Slate sandbox/money note in TESTING.md.
- Tests, make check for both mods, make link, TESTING.md "Showcase" section with exact steps (Blank Slate map,
  which mods, start year, what to screenshot: each town overview + a close-up of a junction for the red sign).
