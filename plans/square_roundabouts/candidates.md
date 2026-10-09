# Candidate additions (2026-10-07)

## Reference: Roadform — Interchanges & Intersections (Steam Workshop 3810308528)
- Transport Fever 2 mod by psyhonut, ~2.9k subscribers. The author says a TF3 port comes next.
- 15 types: diamond, parclo, SPUI, DDI, trumpet, directional T, windmill, turbine S/L, 4-level
  stack, cloverleaf with collector-distributor roads, Gravelly Hill, Michigan left, modern
  roundabout, turbo roundabout, channelized junction.
- Options: traffic side, plus S/L sizes on some types. Unlocks in 1925. Concrete bridges only.
- Complaints:
  - Upgrading roads after placement fails on mm-long stubs.
  - Restyling a viaduct adds junctions.

## Ranked for Better Roundabouts
1. **Roundabout interchange** (one ring over/under a highway, slip ramps), as its own entry. Medium effort.
2. **Dumbbell** (two rings joined by a bridge), as a Layout value of (1). Low-medium effort.
3. **Peanut / dogbone**, as a Layout value of (1). Medium effort.
4. **Hamburger / through-about**: extend "Through the centre" (larger roads, with signals). Very low effort.
5. **Channelized junction** (slip lanes, islands), as its own entry. Reuses the splitter leg code. Low-medium effort.
6. **Parclo**: medium effort, but it widens the scope to an interchange pack.
7. **SPUI**: high effort; it needs signals and large single nodes.
8. **Turbo**: still deferred (no lane discipline with base templates).
- Skip: stack, turbine, windmill, Gravelly Hill, Michigan left.

Quick wins:
- Earlier unlock: check template years.
- A bridge-type param on grade-separated entries.
- A test that no edge is shorter than ~1 m, so road upgrades work.
