# Bulk Bulldozer (`square_bulk_bulldozer`): plan

Status: revision 4, released on mod.io (rev 1 2026-10-07, rev 2 2026-10-08, rev 3 and 4 2026-10-10). Plan
docs restructured 2026-10-12.

A bulldoze **brush** for TF3. Open the tool and a circle of adjustable radius follows the mouse over the terrain. Paint with the left mouse button to **select** everything bulldozable under the circle that your filters allow, then press **Bulldoze** in the toolbar to remove it at the normal bulldoze cost.

## Shipped

- Rev 1: brush tool in Road → Tools and Rail → Tools; Paint selects, the toolbar **Bulldoze** button removes,
  Clear / RMB / ESC / closing the tool clear; one Roads filter; red selection highlight (design below).
- Rev 2: lighter brush reads and reused highlight pieces (`PERF_REVIEW.md`); Shift while painting
  removes objects from the selection.
- Rev 3: optional performance log (mod setting "Debug: performance log", SQPERF); mouse-event log lines only
  with it On.
- Rev 4: translations into all 12 other game languages; status lines shortened by display width.

## Open work and next step

- The `TESTING.md` boxes were never ticked, although rev 1-4 shipped and archived sessions show the tool in use
  (`2026-10-09_0044_sqrl-crash`, `2026-10-09_0658_sqrl`, `2026-10-11_1947_junction-grid-crash`). Next step:
  tick what those logs and the releases already answer, then run what is still open (TESTING §3a highlight
  questions, §4 cost sign / refund / combined proposal, §6 locks, §7 perf).
- "Risks and open questions" below lists the unverified items and their fallbacks.
- v2 ideas: standalone signal / stop removal (no proven API), trees (impossible from script).

Phases 1-5 (skeleton, selection engine, commit path, polish, release prep) are done; their briefs are in
`HISTORY.md`. Evidence for every design decision: `research.md` (cited as "research §N" in the mod code).

## Decisions

| Topic | Decision |
|---|---|
| Interaction | **Brush** (user decision, not box select). **One mode only: Paint** (user decision 2026-10-07; the Paint/Stamp button and Stamp mode were removed). Holding LMB adds everything under the moving circle to the *selection*, highlighted live. **Releasing LMB never removes anything:** the selection stays highlighted (amber ring) and every further stroke **adds** to it, up to the 400 cap. A plain click (no drag) adds what is under the circle. |
| Confirm | **Always select, then confirm** (user decision 2026-10-07). The toolbar button **Bulldoze** (was "Bulldoze selection", renamed 2026-10-07 because the bar clips button text) removes the whole selection: a one-value `ScriptParamType.Button` with `hideLabel`, whose `onChangeFn` fires `BulkBulldozer.bulldoze` → `react.onEvent` (the same toolbar bridge as radius/filters). `construction.tl` `changeParam` (1866-1897) calls `onChangeFn` on every click even when the value is unchanged, and the Overpass Builder's **Build** button uses exactly this pattern (`overpass_probe.script.tl:6105-6130`). With nothing selected the status chip shows "Nothing selected / Paint over objects first" for 3 s. **No keyboard shortcut:** `IA_APPLY` is the left click / gamepad A in construction tools (`internal.css.lua:1002-1075`) and there is no proven key-event path for Enter/Delete in base or subscribed code. |
| Toolbar (user request 2026-10-07, research §10) | Order: Radius · **[Bulldoze] [Clear]** (one-value Buttons, `hideLabel`, same `group` → one row, `construction.tl:2024-2074`; labels from `makeCompactButtonFn` as `BoxLayout{TextView}` because the bar fixes a direct button TextView to 50 px, `construction.css.lua:820-823`) · **status chip** (one-value Button, no group, `checkEnabledFn → "Disabled"`, content = our self-updating `BulkBulldozerStatus` recipe: module-level `g_status` polled on `onStep` + `BulkBulldozer.status` event) · 6 filter CheckBoxes (`group` = filters, separator above; 7 until the Roads merge). Chip text is pure (`bb_status.tl`): headline + detail, ≤ 36 characters each (tune in game). Rejected: dynamic `formatValueFn`, runtime `values` swaps, a separate window, keeping it in the tooltip. |
| Clear / exit | The **Clear** button, RMB or ESC while something is selected (or a stroke is being painted) **clears the whole selection** (nothing is removed). RMB when nothing is selected does nothing. ESC when nothing is selected falls through to the base menu (closes the construction window, like base custom tools, `construction_react_util.tl:1437-1441`). **RMB (research §12):** cleared on the RMB `Clicked` (or `Released`) event, because RMB `Pressed`/`Released` never reach the Selector in game; a release more than `RMB_CLICK_MAX_PX` = 16 px from the press (`PressedOutside`) is a camera drag and keeps the selection. **Closing (user feedback 2026-10-07):** leaving the entry, closing the construction window, switching to another tool or hiding the menu empties the selection and resets the status chip, so reopening starts empty: recipe `onMount`/`onUnmount`, an `isActive == false` render and the world layer's unmount (not remounted within 0.25 s) each call `resetAll`. No timer-based clear: an idle, paused or unfocused open tool keeps its selection. |
| Where it lives | A `construction_tool` resource with a custom action (`ACTION_CUSTOM`), the same mechanism as the base Locking/Marketing tools and the Overpass Builder mod. Menu entries: **Road → Tools** (`roads_tools`) and **Rail → Tools** (`rail_tools`), `order = 5` (head of the category; see the gamepad note in research §1). The base Bulldozer tab is code-built and can't take mod entries. |
| Radius | Toolbar slider with `numbers` {5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 200} m, **default 20 m**. The 200 m cap bounds query cost and accidents. |
| What a stroke hits | **Edges:** touching. The edge's curve (Hermite from `position0/1`, `tangent0/1`, 9 samples) comes within the radius of a brush sample. **Constructions:** the origin (`transf` translation) is inside the circle. Nodes are never targeted directly. Rule constants live in `bb_select.tl` so they can be tuned after in-game tests. |
| Filters (toolbar checkboxes, defaults) | **Roads** ✔ (user decision 2026-10-07: every street that is ours or has no `PLAYER_OWNED`, i.e. town roads and roads freed from street constructions too; there is no way to tell town roads from unowned player roads, research §12. Replaced "Your roads" ✔ / "Town roads" ✘) · **Tracks** ✔ · **Stations & depots** ✘ · **Other assets** ✔ (player-owned constructions that are not stations, depots or industries, e.g. placed assets) · **Town buildings** ✘ · **Underground** ✘ (`BaseEdge.type == TUNNEL` edges, like the base bulldozer's Underground toggle). Bridges count as normal roads/tracks. |
| Never removed (hard rules) | Industries (any construction with `#industries > 0`), the player HQ (`PLAYER.headquarters`), non-player constructions other than town buildings (landmarks, mission props), anything owned by another player, edges/nodes that belong to a construction (`getConstructionEntityForEdge/Node >= 0`; they go with their construction), entities that no longer exist. There is no toggle for industries in v1. |
| Signals, waypoints, stops | Removed **only with their edge**: an edge's `BaseEdge.objects` go into `edgeObjectsToRemove` in the same proposal (or `makeSegmentsRemoveProposal` handles them). Removing just the object and keeping the edge has no proven API, so it's a v2 item. |
| Trees / vegetation | **Not possible from script** (no command; only the native asset brush with `eraseWhenEmpty`, research §5). Out of scope. The description points to the base Vegetation Eraser. |
| Vehicles | Out of scope. An edge or station with a vehicle on it fails validation and is reported as skipped. |
| Batching / rate limit | **One commit per confirmed selection.** While painting, a brush sample is taken on `react.onStep` only when the cursor moved ≥ radius/4 since the last sample, or 100 ms passed (`os.clock`). Each sample runs the octree queries and merges hits into a set. The selection is capped at **400 entities**; past that, samples stop adding, the status chip shows "400 selected (max)" and the tooltip "Limit of 400 reached". |
| Confirmation | Every selection waits for **Bulldoze** (the old threshold rule, > 40 objects / station / cost > 10 % of balance, was removed with the 2026-10-07 decision). While a selection exists the status chip reads "N selected · cost" over the counts per kind; the tooltip says "Right-click clears the selection". A preview cost above the balance still refuses the whole commit ("Nothing bulldozed: not enough money"). No window, so none of the window/recipe crash classes apply. There is **no undo** in TF3 (research §5), which is why nothing is removed without the explicit button press. |
| Highlight (user report 2026-10-07, research §11) | `bb_highlight.MODE`: `"both"` (default) = engine tint through the Selector selection colours (red `#CE2029`; hover preview light coral, fainter) **plus** overlay lines along selected edges and circles on selected constructions in the ring's EdgeRenderable; `"engine"` = tint only; `"lines"` = lines only (Selector transparent). `HOVER_ONLY_HIGHLIGHTED = true`: the Selector filter accepts only highlighted entities, so the hover effect never marks an unselected object. While a selection exists only it is highlighted; the ring shows where the brush is. Overlay cap `MAX_SEGMENTS` = 1600 pieces (~15 m each, max 8 per edge), cached per selection change. |
| Cost preview | `makeProposalData(SimpleProposal)` (cast, as in the Overpass mod) gives `costs` + `errorState`. It is computed at most 4×/s while the selection grows, once when LMB is released and once more (fresh preflight) when the button is pressed, and shown in the toolbar status chip. |
| Commit and errors | `makeWorldBuildProposalCmd(p, Context.new(), ignoreErrors = false, playerInitiated = true, doDust = true)`. `ignoreErrors=false` because we can't read mission locks (`BulldozerInfo` isn't a component type), so the build must refuse them. **On failure, split**: halve the batch and retry each half, recursively, down to singles, with a hard cap of 48 commands per stroke. What still fails is counted and shown ("3 skipped: vehicle in the way / locked"), using `errorState.messages` from a preflight on the failing single. Constructions and edges go in **one** SimpleProposal (`constructionsToRemove` + `streetProposal.edgesToRemove/edgeObjectsToRemove/nodesToRemove`). If Phase 2 shows the engine needs the base two-step (constructions first, then `makeSegmentsRemoveProposal` in the callback, `industry_util.tl:560-601`), switch to it. |
| Orphan nodes | After choosing edges, add nodes that would be left with no edge (degree from `getNode2SegmentMap()` once per commit, minus the removed edges) to `nodesToRemove`, unless they're frozen (construction-owned). Phase 2 checks whether the engine does this itself. If so, drop it. |
| Threads / state | Everything runs in the GUI custom-action recipe (GUI thread). **No game script, no saved state**, no modifiers. Timing uses `os.clock()`. The definition-VM rule (research §6): nothing computed in `getDefinition` is used at runtime. Toolbar values reach the recipe through `onChangeFn` → `api.gui.fireReactEvent` → `react.onEvent`, the proven Overpass bridge. |
| mod.json | `severityAdd: None`, `severityRemove: None` (stateless: removing the mod only removes a menu entry; precedent `move_it_probe_overpass/mod.json`). **`cosmetic: false`**: it changes the world (the wiki excludes anything with simulation impact, `moddefinition.md:69`). The user can flip it if they consider it equal to the base bulldozer. |
| Conventions | modId `square_bulk_bulldozer`, author "square", Teal scripts, `_metadata/description.html` with Changelog, `branding/mods.js` cover entry (Phase 5). Strings in `strings.json` (`en` first). No file or resName containing "eraser" (`construction.tl:4021` hides single-"eraser" categories). |

## Architecture

```
mods/square_bulk_bulldozer/
  mod.json                          revision 1, severities None/None, cosmetic false
  strings.json                      en (+ de later)
  _metadata/modinfo.json, description.html, 0.png
  content/bulk_bulldozer/
    bulk_bulldozer.res.lua          { type = "construction_tool", getDefinitionFn = bulk_bulldozer.script@getDefinition }
    bulk_bulldozer.script.tl        getDefinition (params, menuCategory, customAction) + BulkBulldozerAction recipe:
                                    actionFn → ActionDescriptor{ Selector, EdgeRenderable (circle), ActionTooltip, highlightedEntities }
    bb_types.d.tl                   Filters, Candidate {entity, kind, reason}, Stroke, BatchPlan
    bb_brush.tl                     PURE: radius list, ring segments (N arcs + heights via injected fn), sample-throttle policy,
                                    edge-touches-circle (Hermite sampling), point-in-circle
    bb_select.tl                    PURE: classify(descriptor, filters, player) → keep | skip(reason); selection set + cap
    bb_batch.tl                     PURE: split plan for failed batches (halving, cap 48), orphan-node computation from a degree map
    bb_gather.tl                    API layer: octree queries → plain descriptors (each getComponent in pcall), node degree map
    bb_commit.tl                    API layer: SimpleProposal build, makeProposalData preflight, sendCommand + split retries
    bb_status.tl                    PURE: toolbar status chip text (selection, hover preview, results), clipping
    bb_highlight.tl                 PURE: highlight mode, colours per phase, overlay line pieces along edge curves
    bulk_bulldozer.css.lua          prompt hints (`!input-mouse R::BulkBulldozerAction`), optional
    bulk_bulldozer@2x.tga, bulk_bulldozer_preview@2x.tga   menu icons
tests/square_bulk_bulldozer/test_action.lua (RMB + close handling, fake react), test_brush.lua, test_select.lua, test_gather.lua (fake api), test_definition.lua, test_batch.lua, test_commit.lua (fake api), test_status.lua, test_highlight.lua
tools/render_icon_square_bulk_bulldozer.py   menu icon renderer (pattern: tools/render_icon_square_roundabouts.py)
```

Data flow (one stroke):

1. Pressed LMB: start a new selection, or continue the existing one.
2. Each step while held: if the throttle allows, `gather(center, r)` → descriptors → `classify` → add keeps to the set.
3. The set feeds `highlightedEntities` and the toolbar status chip.
4. Released LMB: cost preview; the selection stays and waits (more strokes add to it; RMB / ESC clear it).
5. **Bulldoze** pressed: `commit(set)`: preflight (money check), send, split on failure, then report in the status chip for 3 s and in the log (`[BulkBulldozer]`).

Gather per sample:
- `octree.findEntitiesInCircle(c, r + EDGE_MARGIN, BASE_EDGE)`. `EDGE_MARGIN` = 0 if the octree tests geometry, otherwise roughly half the longest edge length (set in Phase 2), then the exact touch test in `bb_brush`;
- `findEntitiesInCircle(c, r, CONSTRUCTION)`;
- for each kept edge, its `BaseEdge.objects`.

Classification uses only copied plain values (`BaseEdge.type`, has `BASE_EDGE_STREET`, `PLAYER_OWNED.player`, construction lists, owning-construction ids), so `bb_select` is unit-testable.

## Phases

Done. See "Open work" above and `HISTORY.md` for the phase briefs.

## Risks and open questions (need in-game answers)

- **Selection highlight (research §11).** Unverified: that the Selector colours tint `highlightedEntities` on edges, constructions and town buildings (base only does it for vehicles), that a fill colour shows as a tint, that the filter-restricted hover keeps clicks working, and that reusing cached EdgeRenderable edge objects across renders is fine. Fallbacks: `MODE = "lines"` if the engine tint looks wrong; `HOVER_ONLY_HIGHLIGHTED = false` if clicks or the tint break; rebuild the overlay every render if cached edges vanish.
- **Toolbar values vs filters used (fixed, research §12).** `getCurrentParams()` returns `{}`, so the filters come from `checkEnabledFn` params + `onChangeFn` events in file-scope memory; unknown/conflicting → OFF (safe direction: a ticked box may select nothing, never the reverse). Residual risk: if the menu passed stale params to `checkEnabledFn` on a category switch, a kind could be used ticked/unticked as in the other category until the next toolbar change; every sync logs `filters (…)`, TESTING §3 checks it.
- **Right click / closing (research §12).** Unverified: that RMB `Clicked` clears in game, that 16 px separates a click from a camera drag, and which of the four close detectors fires (each logs its reason).
- **Status chip (research §10).** Unverified: that a recipe renders as ToggleButton content, that the disabled grey chip is readable and that 36 characters fit. Fallbacks: drop `"Disabled"` (chip looks like a button but stays inert), shorten `bb_status.MAX_CHARS`, or show only the headline.
- **Left-drag and the camera (Phase 1).** If LMB-drag pans the camera and returning `true` doesn't stop it, painting can't work as written. Fallbacks, in order:
  - (a) Paint while **Shift** is held. There is no key-state query in `api.gui`, only key events (`Gui.Key.Event`, `getKeyMod`, `gui.d.tl:268-292`), so Phase 1 checks whether the recipe receives them;
  - (b) Paint toggled on by a click (click starts painting, click again stops);
  - (c) click-only selection: every click adds what is under the circle (already works: a plain click adds on `Released`, which is proven), and the selection is built up click by click.
- **"Bulldoze" / "Clear" buttons.** Assumed to fire `onChangeFn` on every click (Overpass Build pattern). If a second click on the one-value button does nothing in game, give it two identical values with a cycling `stepValueFn` (like the base Underground button) so every click changes the value.
- **Octree hit semantics (Phase 1/2).** It's unknown whether it uses the position or the bounding volume. That decides `EDGE_MARGIN` and whether large constructions are found when the brush is over them but not over their origin. If constructions are only found by origin, consider a second pass with `BOUNDING_VOLUME` (component exists, `engine.d.tl` ComponentType list).
- **`getCurrentParams()` content (Phase 1).** If it holds indices, map them through the same `numbers` table. The `fireReactEvent` bridge is the default anyway.
- **Locks and `ignoreErrors` (Phase 3).** We can't read `BulldozerInfo.locked`. We assume a build with `ignoreErrors=false` refuses locked entities. Test this in a campaign mission save with a locked object. If it doesn't refuse, the mod must not run during missions (`api.gui.mission.getMission() ~= ""` → disable the tool with `DefinitionDisabled`).
- **Costs and refunds (Phase 3).** Does `playerInitiated=true` charge bulldoze costs, give the 75 %/60 s refund (`mod.script.tl:30-31`) and journal under Bulldozer? If it charges nothing, the mod is a free bulldozer, which is a balance issue. Then book the preview cost with `makeJournalBookAssetCmd`, as the base marketing tool does (`marketing_campaign_tool.script.tl:98-102`).
- **Combined vs two-step proposal, orphan nodes, edge objects (Phase 3).** Settled by test. The plan supports both.
- **Station removal side effects.** The base proposal updates lines and stops (`type.d.tl:2826`). Stations stay off by default.
- **Town reaction.** Removing town roads or buildings may hit town rating the same way the base bulldozer does. That's why both are off by default.
- **EdgeRenderable visibility.** Check whether the ring shows through hills and under bridges (`ignoreDepth`). If it can't be made legible, fall back to `api.gui.mission.setZoneCircle` with a fixed key, removed on unmount (in campaign it must not collide with mission zone keys; prefix `square_bulk_bulldozer.`).
- **Standalone signal or stop removal:** no proven API. v2: replace the edge (remove + re-add a copy without the object).
- **Trees:** impossible from script in v1.
