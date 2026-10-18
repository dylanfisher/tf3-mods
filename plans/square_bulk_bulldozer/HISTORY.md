# Bulk Bulldozer: history

Finished phases, superseded status notes and moved checklists, verbatim, newest first. Read only to learn why
something is the way it is. Current state: `PLAN.md`; open checks: `TESTING.md`.

## 2026-10-12: moved from TESTING.md (header notes of the 2026-10-07 builds)

**Current build (Phase 3 + user decision 2026-10-07):** §1-6 apply (§1-3 were never run, so do them first; their questions still matter). **One mode only (Paint), always select then confirm:** strokes only select (releasing LMB removes nothing; the selection stays highlighted and later strokes add to it); the toolbar button **Bulldoze** removes the whole selection. **Clear**, RMB or ESC clear it. **Toolbar rework (2026-10-07):** [Bulldoze] [Clear] sit side by side, a grey status chip under them shows the live selection (it replaced the selection lines of the cursor tooltip, which now only has the radius, a right-click hint, skip reasons and the debug octree line). §1 has the new checks. **There is no undo: use a save copy.** Default proposal mode is the base **two-step** (`bb_commit.COMBINED_PROPOSAL = false`: constructions first, then the edges via `makeSegmentsRemoveProposal`); §4 asks to retest a few cases with `true`.

**Feedback round (2026-10-07, research §12), test first:** (1) one **Roads** CheckBox (default on) replaces "Your roads" / "Town roads" and takes every street that is yours or unowned (town roads, roads left over from a roundabout); (2) **right click** now clears on the RMB release (the press never reached the tool, see the log lines below); an RMB **drag** (camera) keeps the selection; (3) **closing / switching the tool empties the selection** and the status chip. Checks: §1 (Roads), §3 (Roads), §5 (RMB, closing).

**Highlight fix (2026-10-07):** the selection is now shown in the world (research §11): a **red tint/outline** from the engine on selected objects (light coral, fainter, for the hover preview before anything is selected) **plus red lines** along selected roads/tracks and a **red circle** on each selected construction's centre. Do **§3a** first.

## 2026-10-12: moved from PLAN.md "In-game test checklist (TESTING)" (superseded by TESTING.md)

## In-game test checklist (TESTING)

Use a **copy** of a save. Run `make link`, enable the mod, then tail the log:

```sh
tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered -i "BulkBulldozer\|square_bulk_bulldozer\|error"
```

1. **Mounting (P1).**
   - [ ] Road → Tools and Rail → Tools show "Bulk Bulldozer" at the head of the list with its icon.
   - [ ] Selecting it shows the toolbar (radius slider, [Bulldoze] [Clear], status chip, filters).
   - [ ] Switching to another entry or closing the menu removes the ring.
   - [ ] ESC closes the menu.
   - [ ] No Lua error in the log.
2. **Brush + mouse (P1).**
   - [ ] The ring follows the cursor, hugs hills and valleys, and resizes 5 → 200 m with the slider.
   - [ ] Log: LMB Pressed/Released arrive; Moved arrives while LMB is held (yes/no).
   - [ ] Left-drag over terrain: does the camera move? With `return true` on Pressed?
   - [ ] Log: `getCurrentParams()` radius value (index or metres).
   - [ ] Tooltip counts: hover the middle of a long straight track edge with a 5 m brush away from its centre (is the edge counted?), and a big station away from its origin.
3. **Selection (P2).** In a town, a station area and an industry area, paint without committing.
   - [ ] Highlights follow the filters.
   - [ ] Industry parts, its roads, the HQ and other players' or mission objects are never highlighted.
   - [ ] Every street (yours, town, freed from a roundabout) with "Roads"; other players' and station/industry roads never.
   - [ ] Tunnels only with "Underground".
   - [ ] Station access roads that belong to the station are not highlighted separately.
   - [ ] The 400 cap message appears with a 200 m brush in a city.
4. **Commit (P3).**
   - [ ] Releasing a stroke removes nothing; more strokes add to the selection; **Bulldoze** removes it in one go, with dust.
   - [ ] Money drops by about the preview cost, and the journal shows it under bulldoze/construction.
   - [ ] Re-bulldoze something built < 60 s ago: is it refunded?
   - [ ] Tracks with signals are removed together with the signals.
   - [ ] No orphan nodes are left (click the former junction spot).
   - [ ] A track with a train on it is skipped and reported; the rest of the stroke is removed.
5. **Guards (P3).**
   - [ ] Clear / RMB clear the selection; nothing is removed. An RMB drag (camera) keeps it.
   - [ ] Leaving the entry, closing the menu or switching tool empties the selection; reopening starts empty.
   - [ ] ESC clears the selection (mid-stroke too).
   - [ ] With money below the cost, the commit is refused and reported; nothing is removed.
6. **Locks (P3).** In a campaign mission save with a non-bulldozable object:
   - [ ] the object is refused, not removed;
   - [ ] the result is recorded (decides the mission-disable fallback).
7. **Perf (P4).**
   - [ ] A 200 m brush dragged over the densest city stays smooth.
   - [ ] Log the worst sample time (target < 2 ms).
8. **Save safety (P4).**
   - [ ] Add the mod to an existing save: no warning; the tool works.
   - [ ] Remove it: no warning; the save loads and nothing changed apart from what was bulldozed.
   - [ ] Achievements: note whether they are disabled (expected with `cosmetic: false`).

## 2026-10-12: moved from PLAN.md "Phases" (Phases 1-5 done; rev 1 released 2026-10-07)

## Phases

Each phase runs in its own subagent. Every brief includes: this plan's path, the scope, the file boundaries, the memory constraints (pre-5.3 Lua; `.tl` modules return tables; no `mouseTransparent` on ImageView; no Component-wrapped recipes; GUI-thread APIs only in the GUI recipe; mod must not affect saves) and the done criteria. Done always includes `make check MOD=mods/square_bulk_bulldozer`, `make test MOD=mods/square_bulk_bulldozer` (from Phase 2) and `make validate MOD=mods/square_bulk_bulldozer`.

1. **Skeleton + interaction spike.** Scaffold the mod (`make new-mod ID=square_bulk_bulldozer NAME='Bulk Bulldozer'`, Teal, tag "Script Mod"), then write `.res.lua`, `getDefinition` and the action recipe with:
   - the radius slider (no filters yet; the Paint/Stamp button it had was removed on 2026-10-07);
   - the ring drawn with one `EdgeRenderable` of 48 terrain-following arcs;
   - a Selector with transparent selection colours, `onSelect` returning true, and an `onProcessMouseEvent` that **logs** Pressed/Released/Moved/Wheel (button, `handled`) and returns `true` for LMB Pressed/Released;
   - a tooltip showing "r = 20 m · N edges · M constructions" from live octree counts.

   It removes nothing yet, and uses a placeholder icon (any 32-bit TGA via the icon script stub).
   **Done:** offline checks pass, plus an in-game report (TESTING §1-2) that answers:
   - the menu entries appear in Road → Tools and Rail → Tools;
   - the ring follows the cursor and terrain and resizes with the slider;
   - whether a left-drag moves the camera, and whether returning `true` stops it;
   - whether `Moved` arrives while LMB is held;
   - whether `getCurrentParams()` returns indices or numbers;
   - the octree hit semantics (does a long edge whose bounding box overlaps a small circle away from its centre show up?).
2. **Selection engine (pure + gather).** `bb_types.d.tl`, `bb_brush.tl`, `bb_select.tl`, `bb_gather.tl`:
   - the full filter set as toolbar CheckBoxes (`values = {Off, On}`, 2 = on);
   - the hard rules, live highlight via `highlightedEntities`, the stroke set with throttle and 400 cap.

   Still **no removal**: the tooltip lists counts per kind and per skip reason. Unit tests cover: touch test (straight/curved edges, edge fully outside, tangent edge), every filter × entity kind, hard rules (industry, HQ, foreign owner, construction-owned edge, tunnel), throttle policy, cap.
   **Done:** checks + tests pass; TESTING §3 run in game (highlight matches expectation in a town, a station area and an industry area; no industry or HQ part ever highlighted).
3. **Commit path.** `bb_batch.tl`, `bb_commit.tl`:
   - SimpleProposal build with edge objects and orphan nodes;
   - `makeProposalData` preflight (cost + errors in tooltip);
   - send with `ignoreErrors=false, playerInitiated=true, doDust=true`;
   - split-on-failure retries (cap 48), skipped-count report;
   - the confirmation step (now: the **Bulldoze** toolbar button), Clear/RMB/ESC clear.

   Unit tests: split planner (all fail, one bad item at each position, cap), orphan nodes (shared node kept, dead-end node removed, frozen node never).
   **Done:** checks + tests pass; TESTING §4-6 in game, which also settles: the sign and meaning of `costs`; bulldoze charges and refunds in the finance window; whether one combined proposal works or the base two-step is needed; whether the engine removes orphan nodes itself; that a mission-locked or vehicle-occupied item is refused, not removed.
4. **Polish + safety review.**
   - Brush colours: ring white idle, red while painting, amber while the selection waits for the button.
   - Prompt hints CSS, `strings.json` (en; de if cheap), final icons via `tools/render_icon_square_bulk_bulldozer.py`.
   - Log hygiene: `[BulkBulldozer]` lines, failures always on, debug behind a flag.
   - Perf check: a 200 m brush over a dense city stays under ~2 ms per sample (measure with `os.clock` and log the worst case).
   - Code review against the memory notes.

   **Done:** checks + tests pass; TESTING §7-8 (perf, add/remove mod from a save).
5. **Release prep.**
   - `_metadata/description.html` (features, filters, "no undo, use filters", trees → Vegetation Eraser, Changelog rev 1);
   - `modinfo.json` summary/tags;
   - `branding/mods.js` `Square.register` entry (accent distinct from existing; pictogram: dashed circle over a road stub), then `make covers MOD=mods/square_bulk_bulldozer`;
   - gallery shots later from `plans/square_bulk_bulldozer/shots/`.

   **Done:** `make validate` clean, cover rendered, TESTING all ticked.

## 2026-10-12: moved from PLAN.md status paragraphs (2026-10-07)

**Status (2026-10-07, in-game feedback round):** three fixes from the user's first test (research §12). (1) **One "Roads" filter** (default on, key `bulk_bulldozer_f_roads`) replaces "Your roads" / "Town roads": every street that is ours or unowned (town roads, roads freed from street constructions such as roundabouts) is kind `road`; hard rules unchanged (never another player's, never a construction's, never an industry road). (2) **Right click**: the log showed RMB never reaches `onProcessMouseEvent` as Pressed/Released, only as `PressedOutside` + `Clicked` (the press is bound to IA_MENU_BACK / IA_BACK / IA_CLOSE_TOPMOST_WINDOW / IA_CONSTRUCTION_ACTION_CANCEL); it now clears on RMB `Clicked`/`Released` unless the mouse moved > 16 px (camera drag), logging every RMB release. (3) **Closing / switching the tool empties the selection**: the log had no `tool deactivated` line at all, so the selection lived on in the still-mounted recipe; now recipe mount/unmount, an inactive render, and the world layer's unmount (not remounted within 0.25 s) each reset the selection and the file-scope status chip (a 5 s "no step" detector was dropped: it could fire while the game window is unfocused). (4) **Toolbar sync (safety):** the filters used can no longer differ from the CheckBoxes shown in the unsafe direction: they come from the params the menu passes to `checkEnabledFn` on every activation/change and from the `onChangeFn` events (with menu category), kept in file-scope memory that is NOT reset on close; unknown or conflicting values count as OFF and are logged (`bb_select.resolveFilters`, research §12). `make check`, `make test` (118 tests, new `test_action.lua`) and `make validate` pass (validate warns only about the Phase 5 cover). Next: TESTING §1, §3 (Roads), §5 (RMB, closing).

**Earlier status (2026-10-07, toolbar rework):** after the first in-game look (screenshot: "Bulldoze selection" clipped on a full-width button; Town roads ticked), the toolbar now reads, top to bottom: **Radius** slider · separator · **[Bulldoze] [Clear]** side by side · a grey **status chip** with the live selection ("12 selected · $34,500" / "8 roads · 3 tracks · 1 asset", hover preview, "Bulldozing…" and results for 3 s) · separator · the 7 filters. The cursor tooltip shrank to the radius, a right-click hint, skip reasons and the debug octree line. Mechanism and evidence: research §10 (row "Toolbar" below). Town roads ✔ was a value toggled earlier in that session (menu keeps toolbar values per category for the session), not a default bug. `make check`, `make test` (93 tests) and `make validate` pass (validate warns only about the Phase 5 cover). Next: TESTING §1 (toolbar look) then §2-6.

**Highlight fix (2026-10-07, user report "selected objects are not highlighted, only counts"):** root cause: the Selector's selection colours were transparent (Overpass pattern), and the engine draws `highlightedEntities` with those same colours (research §11). New pure module `bb_highlight.tl` (`MODE` = `"both"` by default): the Selector now uses the base palette red (`#CE2029`, lighter coral for the hover preview), its `filter` accepts only highlighted entities (no hover effect on anything else), and red lines along every selected edge + a red circle on every selected construction are drawn in the ring's single EdgeRenderable (cap 1600 pieces). `make check`, `make test` (106 tests) and `make validate` pass. Next: TESTING §3 highlight checks.

**Earlier status (2026-10-07):** User decision applied on top of Phase 3: **one mode (Paint), always select then confirm.** The Paint/Stamp button, Stamp mode and the threshold confirmation rule are gone; a stroke never removes anything on release, later strokes add to the selection (400 cap), and the toolbar button **Bulldoze selection** removes it (cost preview and "not enough money" refusal kept). RMB / ESC clear the selection. `make check`, `make test` (78 tests) and `make validate` pass. Still no in-game run of any phase.

Earlier: Phase 3 (commit path) implemented offline on top of Phases 1-2: `make check`, `make test` (77 tests) and `make validate` pass (validate warns only about the Phase 5 cover). The tool now **removes** what it selects (no in-game run yet of any phase: `TESTING.md` §1-6, in order). Flags to settle in game: `bb_commit.COMBINED_PROPOSAL` (default **false** = base two-step: constructions in a SimpleProposal, then edges via `makeSegmentsRemoveProposal` in the callback, research §9; `true` = one SimpleProposal with edge objects + orphan nodes), `bb_commit.CONTEXT_WITH_PLAYER` (default true: Context carries player + refundable entities like the base buy path). Phase 3 also fixed station ownership (station group / depot `PLAYER_OWNED` when the construction has none, fail-safe) and confirmed CheckBox values are 1-based in `getCurrentParams` (research §9). Earlier choices still pending the spike: `EDGE_MARGIN` = 100 m, origin-only construction hits (`bb_select.CONSTRUCTION_ORIGIN_ONLY`), industry roads protected via `findSegmentsToDelete(con, false)` and frozen-node ownership (research §8).
