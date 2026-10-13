# Roundabouts mod: feasibility review (2026-10-07)

Status: done 2026-10-07 (feasibility review before Phase 1).

## Vanilla baseline

`base/content/infrastructure/street_construction/roundabout.con.lua` + `street_constructions.script.lua:632` (`updateFnRoundabout`):

- 4 Bézier quarter edges (handle `r*4*(√2-1)`), z = 0, counter-clockwise (right-hand traffic only).
- Params: lanes {1, 2, 4} → `highway_new_small`, `town_new_one_way_small`, `town_new_one_way_medium`; radius 15–60 m.
- No arms, no centre island (`models = {}`, `groundFaces = {}`), cost 0, available from 1960.
- `freeNodes = freeAllNodes(edges)`, `snapNodes = {}`: a "stamp" that leaves ordinary, editable streets.

## What the API allows (sources)

| Need | Mechanism | Status |
| --- | --- | --- |
| Ring + arms in one placement | multiple `edgeLists`, nodes merged by string tags in the edge's 3rd element (`docs/wiki/modding/constructions/basics.md:640-690`) | documented, used by vanilla interchanges |
| Arms at arbitrary angles | ring split into N edges at arm angles, `street_util_serialized.addEdgeAutoTangents` | geometry only, no engine risk |
| Mixed street types | one edgeList per template | vanilla interchanges |
| Grade separation | `edgeType = "BRIDGE"`/`"TUNNEL"` + `edgeTypeName`, 3D nodes | vanilla interchanges (`script.lua:249`) |
| Centre island | `subconstructions[i].models` / `groundFaces` / `colliders` / `terrainAlignmentLists` | documented (`basics.md:370-540`) |
| Custom ring street (3 lanes, no sidewalk, apron) | own `.street_template.lua` + `.street.lua` in mod `content/infrastructure/street/` | official mission_04 ships templates; TF3 auto-discovery and no-sidewalk lane lists unverified |
| UI options | params: `Button`, `Slider`, `ComboBox`, `IconButton`, `CheckBox`; `checkEnabledScript` hides/disables params conditionally (`api/type.d.tl:1728-1810`) | documented, `checkEnabledScript` has no base example |
| Rotation hotkeys | `paramsutil.makeRotationParam` | documented |
| Traffic lights at entries | `edgeLists[].trafficLightYes/No` (tealdef) vs `trafficLightNodePreference` (wiki) | names conflict, no base use, unverified |
| Reconfigure after build | `postConstructionModifiable = true` on params | only if nodes are *not* freed |

## Hard limits

1. **updateFn is pure.** It gets only `(captureParams, params)` and can't read the road network, so it can't auto-detect approaching roads. Arm count, angles and length must be params.
2. **No yield/priority control from a construction.** The template `priority` field is documented for junction markings only. `BaseEdgeStreet.precedenceNode0/1` (YES/NO/AUTO, `api/engine.d.tl:146`) and node `laneConnections` exist, but only through a script proposal on built edges. Getting "ring has priority" would need a separate game-script tool, not just the construction.
3. **Stamp vs construction trade-off.** Freed nodes give editable plain streets but no reconfiguration. Unfreed nodes allow reconfiguration but the player can't edit or bulldoze single edges, and arm tips have to be `snapNodes`.
4. Bridge segments are limited to about 100 m, and street templates have slope limits.

## Proposed roundabout types

| Type | Build | Risk |
| --- | --- | --- |
| Standard (1/2/4 lanes) | vanilla ring + arms + island | low |
| 3-lane ring | custom one-way template | medium (template) |
| Mini | radius 8–12 m, flat paved island, no models | low (check turning at tiny radius) |
| Oval / elliptical | non-circular Hermite ring, a×b params | low |
| Dumbbell / peanut | two rings joined by a short two-way link | low |
| Turbo (spiral lanes) | concentric single-lane one-way rings with tag-merged spiral offsets (lane separation comes from separate edges) | medium (node spacing, AI merges) |
| Grade-separated interchange | ring on BRIDGE edges over a through highway + 4 ramps | medium |
| Signalised | standard + traffic-light nodes | high (field names unverified) |

Common options: arm count 3–6 + per-arm angle (or preset patterns), arm length, arm street type (town/country, small/medium/large, era-aware old/new), splitter islands (one-way in/out legs merging into two-way), island style (none, grass, trees, fountain/statue, paved), traffic direction (CCW/CW for left-hand traffic), year availability (vanilla is 1960+; old templates allow earlier).

Island model candidates: `assets/landmarks/msc/fountain.mdl`, `lion_statue.mdl`, `assets/vegetation/trees/*`, `assets/buildings/res/hedges/hdg_02*.mdl`, `raised_bed_*`. Ground: `terrain/materials/grass_cutted_01/grass_cutted_01.gtex.lua`, `buildings/shared/building_paving*.gtex.lua`. Standalone suitability unchecked.

## Phase 0 in-game spike (before committing)

1. Fully freed construction: does it dissolve into plain streets, and can single edges be edited?
2. Arms tagged to ring nodes: do they merge, and does traffic route through?
3. Placing over an existing road: auto-splits/connects, or collision error?
4. A mod `.street_template.lua` is discovered; a no-sidewalk 3-lane one-way template works.
5. `trafficLightYes` vs `trafficLightNodePreference`: which one does anything?
6. Do ring vehicles actually get priority at entries (vanilla behaviour)? This decides whether a precedence script is needed.
7. `checkEnabledScript` works (hiding type-specific params).

## Suggested phases

1. Spike (above), as a throwaway `square_roundabouts` dev build.
2. MVP: Standard + Mini + Oval, arms 3–6, island styles, CW/CCW, era templates.
3. Types: Dumbbell, Turbo, 3-lane, grade-separated.
4. Optional: a "fix priority" game-script tool that sets precedence on ring entries if the spike shows bad yielding.
