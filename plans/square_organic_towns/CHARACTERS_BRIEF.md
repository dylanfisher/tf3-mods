Status: done offline 2026-10-14 (NEXT_PHASE_BRIEF 54; PLAN.md 6.3 "Strong characters, roundabout town, densify"); in game: TESTING.md "Strong characters".

# Organic Towns: strong town characters (phase brief, 2026-10-14)

User:
> "add another phase for identifying more characters with strong preference, like deep forest. these should spawn less
> often, maybe 1 or 2 on a map depending on how many cities, and should be very distinct and really push the parameters"

Builds on the deep-forest character (NEXT_PHASE_BRIEF §43, in work in parallel with generated names §42). Start this
phase after both have landed. Rules, as every phase:
- the CLAUDE.md rules: test only this mod (plus dev if touched), cap every loop, crash rule, don't impact saves, 13 languages for any new user-visible string;
- one test at the end;
- the docs per plans/README.md.

## Framework (`ot_character.lua`, pure)
- **Registry.** A registry like the motif framework (`ot_motif.lua`: `register`, `IDS` append-only for saved indices). Deep forest moves into it as the first kind.
- **Each kind** has:
  - `eligible(site)`: a strong site test, 0..1, from what the mod already reads (TERRAIN, water, forest grid, roads, industries, stations, relief, island / spit / cliff, neighbours);
  - `params`: overrides that really push the planner;
  - optional motifs it forces or forbids;
  - a naming hook for generated and landscape names;
  - a `stats` line.
- **Selection** runs once per new map:
  - quota 1 per ~8 towns, at least 1 and at most 3, two only from 10+ towns;
  - never two towns of the same kind, never a metropolis, never neighbours within ~3 km;
  - the highest eligibility wins, with a seeded tie-break;
  - the existing secluded "character" towns (`ot_map.characters`) become one more kind ("secluded") or stay separate; decide and document it.
- **Saved** on the town's frame (an append-only kind index), so the character is stable across reloads.
- **Logs:**
  - one `CHARACTER pick map=... kinds=...` line per map;
  - one `CHARACTER town= kind= score= why= applied=` line per town;
  - STYLE / PLAN / ALLTOWN show `char=<kind>`.
- **Dev:** a Town-tab control to force a kind on the picked town; there is no translations requirement for the dev mod.

## Candidate kinds (implement the ones whose site test is reliable; at least 6)
| Kind | Site | What it pushes |
|---|---|---|
| deep_forest | dense forest ≥ 0.45 | (already in work) winding, locked around trees, clusters in clearings, lanes |
| hilltop (perched borgo) | an isolated hill, the summit ≥ 25 m above the surroundings | compact, very dense core on the summit, streets spiralling the contours, steep lanes, a hard edge at the slope (no sprawl), LEVELS early |
| clifftop / headland | a cliff or headland over the sea | a strip along the cliff edge, terraces stepping back, a promenade street, nothing down the cliff |
| harbour cove | a small bay with steep sides | a tight crescent around the bay, lanes dropping to a quay, very small blocks, high density near the water |
| waterfront / canal | a river or lake shore through the site | streets parallel to the water, several bridges, quays, ribs perpendicular to the shore, extra bridges |
| street village (Strassendorf) | a valley floor or long road | one long main street, houses on both sides, almost no side streets, length 1.5-3 km |
| company town | a large industry within 1.5 km on flat land | a strict grid of terraced rows (workers_terraces) aligned to the works, the main street to the works gate, high density |
| garden city | wide flat open land, era ≥ 1900 | concentric rings + radial boulevards, a green belt (wedge frames), low density, a central green |
| island town | a town on an island | it covers the island, a ring road along the shore, a dense core, a harbour street |
| mountain pass | a pass or saddle between peaks | strung along switchbacks, a few short terraces |
| spa / crescent town | a gentle slope + water or a park | crescents and terraces around a park (crescent / meadow motifs forced), a promenade |
| moorland hamlets | open heath, high and flat | dispersed small clusters (satellite pods) joined by lanes, very low density, no core growth |
| roundabout town (new town) | wide flat open land, a later era (gate about 1950+; French / EU maps may allow rond-points earlier); pairs well with the garden city | main × main crossings become roundabouts, mini ones on minor crossings; distributor roads between neighbourhood cells (Milton Keynes / French ville nouvelle) |

Roundabout town details. The user: "one character could push roundabouts more (the garden city idea made me think of this)".
- Groundwork already exists: PLAN.md "Roundabouts (NEXT_PHASE_BRIEF 2, probe only)", the dev `otd_roundabout` showcase, and `ot_proposal.junctionConnsDir` for one-way ring node configs.
  - It uses `square_roundabouts`' pure geometry via `ug_require` and its presence file, so there is no hard dependency.
  - The two-way ring is the verified default. The one-way ring is experimental.
- The user noted earlier that a roundabout built with a regular two-way street isn't a real roundabout. Verify the one-way ring in the showcase first, with the node configs from `junctionConnsDir`.
- Without `square_roundabouts`, fall back to the mod's own ring builder, or skip the kind and log `why=noRoundabouts`.
- Place rings where the plan's two main pieces cross at the frontier: reserve the spot while it's empty and build the ring instead of the 4-way node. Never rebuild live junctions: removing town edges demolishes houses, and replacing nodes with 2+ edges crashed.
- Add `RB` lines and a `roundabouts=` count on PLAN / ALLTOWN.

## Pushing the parameters
- Each kind sets planner knobs far beyond the normal ranges, within the geometry safety limits: minimum radius, straight-run limit, block size, arm reach, density / frontage brake, LEVELS on or off, locks, lanes, clearing budget, gap rules, motif forcing, satellites / districts on or off.
- Characters always take precedence over the normal style draw and the diversity penalties.
- Stability: once saved, a character never flips.
- Names: generated names lean on the kind ("-on-the-Hill", "Cove", "Wharf", "Garden City", "Spa"); landscape names prefer list names that carry the kind's tag.

## Tests
- Per kind:
  - a fixture site that should pick it;
  - one that must not;
  - the plan's signature metric reaches its target: hilltop density and radius; strip depth for clifftop; the straight-street share for Strassendorf; the grid share for the company town; rings for the garden city.
- Selection:
  - quota by town count;
  - no duplicate kind;
  - no neighbours;
  - deterministic per seed;
  - stable after reload.
- Hug, clear and normal towns are unchanged, or every change is reported.

## Test in game
TESTING.md "Strong characters":
- a map rich in terrain (coast with bays and cliffs, hills, a river, forests, industry), seed U8Qxgisp4I or a richer one;
- Quick 40 years;
- the tour;
- then send the `CHARACTER` lines;
- also add the run to the comparison page.
