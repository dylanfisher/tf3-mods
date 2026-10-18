# Terraforming with a confirmation step: feasibility (2026-10-11)

Goal: edit the terrain, see the cost, reputation change and other numbers, then confirm or cancel.
Research from the local sources (`.cache/game`, `docs/wiki`).

**Verdict (2026-10-11): scrapped.** The vanilla brush can't be held for confirmation or undone. A terrain-shaping
construction does give a cost/reputation preview before the click, but it only places fixed shapes, the change is an
alignment owned by the construction (base height unchanged), and the test pads couldn't be bulldozed. The DEV probe
(`square_terraform_probe`) was deleted; its in-game results are in `docs/findings.md` "Terrain-shaping constructions".

## Verdict

- **A confirmation step on the vanilla terrain brush: not feasible.**
- **Option A, a running total per terraforming session: feasible,** but it only reports after the fact.
- **Option B, a terraforming construction with the normal build preview and click to confirm:
  feasible on paper.** It gives fixed shapes, not a freehand brush. Probe: `mods/square_terraform_probe`, steps in `PROBE.md`.

## Why the vanilla brush can't be confirmed

- The Raise/Lower/Smooth/Flatten/Roughen tools are native `ACTION_TERRAIN_MODIFIER_*` actions
  (`base/content/gui/construction/tools/terrain_tools.script.tl`). Lua only fills a
  `builtin.type.ConstructionAction.TerrainModifier` with mode, brush params, invert and heightmap
  (`base/content/gui/construction/construction_react_util.tl:3375-3402`; type at
  `base/tealdef/scripts/builtin.d.tl:314-336`). There is no preview/commit split and no callback.
- Each dab is applied at once as a build proposal. `towns.script.tl:266-287` charges reputation in
  `apply_command` / `onPreBuildProposal` via `town_util.getProposalStats` (`town_util.tl:1049`), and
  brush volume enters through `api.engine.util.town.getTerrainBrushVolumeImpact(proposal)` (`town_util.tl:1232`).
  The event only reports the change; a script has no way to refuse it.
- **Reverting is not possible either.** `Proposal.terrain.baseHeightMod` is a `GridVec2f` (`api/tealdef/api/type.d.tl:2655`).
  Lua can read it but has no setter, and the constructors only fill one constant value (`type.d.tl:902-935`).
  So a script can't build the inverse edit. The game has no terrain undo, and the community undo mod gives up
  on any change that touches terrain (`.cache/subscribed/undo_tf3_test/content/undo/history.script.lua:1249`).
  Money and reputation are already charged by then, and a revert would be charged again.

## Costs and reputation (what B would show)

- Brush cost per m³: raise `0.75 * 6.0 = 4.5`, lower `0.75 * 7.0 = 5.25`, times `purchaseCostScale`
  (`base/content/base/mod.script.tl:22-23, 225-226`).
- Reputation: `town_util.calculateProposalImpact` (`town_util.tl:851-883`). Terrain alignment volume uses
  the same rate as brush volume (`-0.0000005` per m³, i.e. 2M m³ = 100%). Alignment volume comes from
  `getTerrainAlignmentImpact(proposalData)` (`town_util.tl:1248`). It is multiplied by a coefficient that drops from 1 to 0.5
  as the construction area grows from 10,000 to 50,000 m² (`town_util.tl:1241-1245`). **A large pad would
  cost half the reputation per m³ of the same edit made with the brush.**
- The builder's hover strings, "Reputation: -x%", come from `getProposalStringsFn`
  (`construction_react_util.tl:3812-3862`). It is set for every construction action, so a pad should get that tooltip before
  the click. Q4 in PROBE.md checks this.

## Option B: terraforming construction

- `terrainAlignmentLists` with `EQUAL` / `LESS` / `GREATER`, faces, slopeLow/slopeHigh
  (`docs/wiki/modding/constructions/basics.md:521-546`). The normal construction builder previews it and
  the click is the confirmation step. The construction's param window gives shape, size, height and slope.
- Open questions (PROBE.md):
  1. Does the terrain stay after the construction is bulldozed? The API calls alignments
     "non-permanent modifications" (`api/tealdef/api/engine.d.tl:1736`): `getBaseHeightAt` leaves them
     out, `getHeightAt` includes them. If the terrain springs back, the pad must stay as an entity
     (a small, zero-upkeep marker).
  2. What does the engine charge for an alignment, compared with the brush rate?
  3. Does the builder preview the reshaped terrain before the click? `ProposalData` has
     `terrainPreviewHeightModLocations` / `terrainPreviewHeightModCutFill` (`type.d.tl:2750-2751`).
  4. Is the reputation tooltip shown before the click?
- Constructions can go in the terrain tools' tab: `menuCategory` `landscaping_terrain`
  (`docs/wiki/modding/constructions/menu.md:64`, `terrain_tools.script.tl:27`).

## Option A: session tally (fallback or companion)

A game script reads the same `apply_command` events and sums cost (balance delta) and
`calculateProposalImpact` per town, shown in a small panel with a reset. It is read-only and safe for saves,
but it can't stop an edit.
