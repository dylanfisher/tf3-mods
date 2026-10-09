# square_smart_lanes: in-game test checklist (Phase 1)

Setup: `make link` (staging), new free game (right-hand traffic), mods: Smart Lanes (defaults) and
Better Roundabouts (`square_roundabouts`). No other lane mods. Keep `stdout.txt` open:
`tail -f ~/Library/Application\ Support/Steam/userdata/<steamid>/3493540/local/crash_dump/stdout.txt | grep SQRL`

Expected log per roundabout: one `[SQRL] APPLY ...` line per changed junction, one `WRITE ... success=true`,
then `VERIFY ... same=<n> nodes=<n>`. Anything with `ERROR` or `success=false`: copy the lines into
`plans/square_smart_lanes/` and stop.

## 1. Does the write work?
- [x] Place a Better Roundabouts **2-lane ring, medium arms, 4 arms**. Log: 4 `APPLY` (turbo=true,
      before=6 after=5), `WRITE success=true`, `VERIFY same=4 nodes=4`.
- [x] Open the **Crossing Tool** on one ring junction: outer ring lane only turns into the arm (kerb
      exit lane), inner ring lane goes straight or into the second exit lane; arm kerb lane -> outer ring
      lane, arm second lane -> inner ring lane.
- [x] Do the **painted arrows** on the road surface change (if the game paints them)? Note yes/no.
- [x] Ctrl+Z / Undo (if available): does it undo our write separately from the roundabout? Note.
- [x] 4-lane ring, medium arms: 4 `APPLY` with before=10 after=7, turbo=true.
- [x] 2-lane ring, small arms: before=5 after=4, turbo=false.
- [x] Vanilla roundabout (1-lane): no `APPLY` lines (rule = engine default), no errors.
- [x] Splitter islands On (2-lane ring): 8 junctions `APPLY` (exit nodes exits>0 entries=0, entry nodes the reverse).
- [x] Road / tram through the centre: the axis junctions log `SKIP reason=multi_arm`, turbo=false.
- [x] Magic Roundabout: central two-way ring untouched; mini rings 1-lane: no `APPLY`.
- [x] Clockwise ring (Better Roundabouts direction param): `dir=cw`, Crossing Tool shows the mirror.
- [x] Hand-built ring: draw a circle of one-way streets with the street tool and connect 3 roads.
      Each build that adds an arm logs `APPLY` for that node only, `fresh=false turbo=false`.
- [x] A normal crossroads / a one-way city block: no `[SQRL]` lines at all.

## 2. Does it stick?
- [x] Wait 2 minutes, re-open the Crossing Tool: unchanged.
- [x] Build a road next to (not touching) the roundabout: unchanged.
- [x] Upgrade one arm road (street upgrade tool) or rebuild one ring segment: does the engine regenerate
      those nodes, and does the mod re-apply (`APPLY ... fresh=false`)? Note what happens.
- [x] Edit a node with the Crossing Tool afterwards: the mod does not touch it (no `[SQRL]` line).
- [x] Save, reload: unchanged, no `[SQRL]` lines on load.

## 3. Traffic (the open questions)
- [x] 4-lane ring with 4 medium arms in a busy town, fast forward a few in-game months, watch 3-5 min.
      **Do vehicles change lanes between junctions** (is o3/o4 used at all, does anyone move from o2 to
      o1 mid-segment)? Note what you see.
- [x] Does anything get stuck: vehicles circling forever, queues on one entry lane, the "no path" /
      unreachable warnings on lines through the roundabout?
- [x] Bus or truck line through each arm pair (incl. U-turn back to the same arm): all reachable.
- [x] 2-lane ring with mixed small and medium arms: same checks (turbo=false there).
- [x] Tram-street ring (Better Roundabouts tram option): trams still run, cars use the rule.

## 4. Settings
- [x] "Apply automatically: Off": same.

## 5. Save safety (required)
- [x] **Add to an old save**: load a save made without the mod (with existing roundabouts), enable
      Smart Lanes, load. No `[SQRL]` lines, existing roundabouts unchanged (Crossing Tool), no errors.
      Build a new roundabout: `APPLY` works.
- [x] **Remove from a save**: save the game from the steps above, disable Smart Lanes, load. The game
      loads without a mod warning beyond the usual list, the lane connections the mod wrote are still
      there (Crossing Tool), traffic runs, no errors in stdout.txt / error.json.
- [x] Re-enable and load again: no duplicate writes on load.

Record results (with log excerpts) in this file and the facts in `docs/findings.md`.

---

# Phase 2 step 1: the Smart Lanes road tool (skeleton + probes)

Setup as above (Smart Lanes + Better Roundabouts, `tail -f ... | grep SQRL`). Build a few rings first:
a Better Roundabouts 4-lane ring with medium arms, a 2-lane ring with small arms, and a plain
crossroads of two-way streets. Copy every `[SQRL]` line of this round into `plans/square_smart_lanes/`.

## A. Find the tool
- [x] Roads -> Tools: **Smart Lanes** sits right after the Crossing Tool (same icon for now).
      Log on opening: `[SQRL] TOOL activated=1 order=1250 layout_param=...`. Note whether the entry
      stays selected and usable (mouse), and the game year (bus lane / traffic light tools visible or not).
- [x] Toolbar shows: [Apply to junction | Apply to roundabout] on one row, [Reset] on its own row,
      and a status chip ("Nothing selected / Click a junction or a roundabout"). Labels not clipped?

## B. Hover and pick (probe: can we pick nodes?)
- [x] Hover a ring junction directly, then the arm road near the junction, then the middle of a ring
      segment, then the middle of an arm. Log per change: `PROBE hover entity=.. kind=node|edge
      promoted=true|false d=.. r=.. target=node:<id>|ring:<id>|none`. **Note which kinds appear**
      (does the Selector ever report `kind=node`?) and whether promotion feels right.
- [x] Hover shows: highlighted streets (junction's roads, or the whole ring), a white circle at the
      hovered junction, and a tooltip ("Junction .. on roundabout .. / Click to select").
      Does the highlight go away when the cursor leaves the streets?
- [x] Click a junction: `PICK target=node:<id> ring=.. lanes=.. arms=.. node_kind=arm conns=..`, no
      entity window opens, teal circle on it (smaller circles on the other ring junctions), status chip
      "Junction <id> on roundabout <id> (4 lanes, 4 arms)" + "10 lane connections, 2 exit, 2 entry lanes".
- [x] Click the middle of a ring segment: `PICK target=ring:<id>`.
- [x] Right-click (no drag) clears the selection (`TOOL cleared=right_click`); Esc with a selection
      clears it (`TOOL cleared=esc` or `back`); Esc without one closes the menu as usual.

## C. NodeViewer (probe: does it draw?)
- [x] After a click: `PROBE nodeviewer ok=true target=node:<id> nodes=1 edges=<n>` (or `ok=false error=..`).
- [x] **Do coloured lane lines appear on the junction** (one colour per road they lead into)? Do they
      match what the Crossing Tool shows for that junction? With a ring selected: lines on all its
      junctions? Screenshot either way.

## D. Apply
- [x] Select a junction on the 4-lane ring, Layout **Turbo**, **Apply to junction**: one
      `APPLY src=tool layout=turbo ... turbo=true`, `WRITE src=tool ... success=true`,
      `VERIFY src=tool ... same=1 nodes=1`; chip "Turbo applied to 1 junction". Overlay updates
      (outer lane only exits). Crossing Tool agrees. Other junctions unchanged.
- [x] Same with **Matched lanes**, **Apply to roundabout**: 4 `APPLY ... turbo=false turbo_reason=matched`
      (minus nodes already matching), outer lane continues at every junction.
- [x] 2-lane ring with small arms, **Turbo**, Apply to roundabout: `turbo=false turbo_reason=narrow_exit`,
      chip says "(no exit-only lane: narrow_exit)".
- [x] Press Apply again: chip "... already set", no WRITE.
- [x] Crossroads: Apply says "Not on a one-way ring ..." and writes nothing.
- [x] No automatic Phase 1 lines (`APPLY` without `src=tool`) after a tool write.

## E. Reset (probe: does a remove-only build regenerate the default?)
- [x] Junction from D selected, **Reset**. Log: `RESET mode=remove_only_sent nodes=<id> success=..`, ~half a
      second later `RESET mode=remove_only node=<id> conns_before=7 conns_after=<n> default_model=10
      same=<bool> decision=<keep|model> reason=<..>`. **Copy this line**: it answers the probe.
      - `reason=regenerated same=true`: the engine rebuilt the default by itself.
      - `reason=empty` / `unchanged`: then `RESET mode=fallback_model ...`, `WRITE src=reset success=true`,
        `VERIFY src=reset same=1 nodes=1`.
- [x] Crossing Tool on that junction: back to the game's own connections (outer lane into both exit lanes,
      entries fanning out)?
- [x] Did traffic at that junction stop or behave oddly for a moment during the reset?
- [x] Whole ring selected, Reset: one `remove_only` line per junction.
- [x] Crossroads, Reset: `decision=keep` or `fallback_restore`; the crossroads still has all its lanes.
- [x] Reset, then close the tool at once (Esc / other tool): the `RESET mode=remove_only` lines still
      appear (judged on close), no junction without connections.

## F. Optional
- [x] Gamepad / controller mode: can the tool be opened and used at all? (menu order caveat, PLAN.md)
- [x] Undo (if any) after a tool Apply: what does it revert?
- [x] Save, reload: tool writes kept, no `[SQRL]` lines on load.

## G. Slip-lane junctions (Phase 4, PLAN.md)
Setup: Better Roundabouts, **Channelized Junction**, Layout T, Main road Town medium (2 lanes each
way; repeat with Town large), Side road Town small, Slip lanes Near-side corners, right-hand traffic.
- [x] **Automatic after placing**: log `APPLY kind=slip node=<east> shape=diverge case=B side=right
      lanes=2_->_2_+_2_slip`, one for the west node (`shape=merge`), one for the side road's node
      (`shape=diverge+merge`), then `WRITE kind=slip job=.. nodes=a,b,c success=true` and about half a
      second later `VERIFY kind=slip job=.. same=3 nodes=3`. No `SKIP kind=slip` for the centre or
      the arm ends. Copy the lines.
- [x] **Crossing Tool** on the east (diverge) node: westbound kerb lane -> both slip lanes and the
      kerb through lane; second lane -> second through lane only; eastbound lanes straight 1:1; no
      U-turns, no crossing lines. West (merge) node: slip lanes -> the kerb lane only, through lanes
      1:1. Side road node: northbound + slip -> kerb lane; southbound kerb lane -> slip and straight.
      Screenshot each.
- [x] Before that, **what did the engine make** at a slip node? Place a second Channelized Junction
      with Apply automatically Off and copy the Crossing Tool picture of one diverge and one merge
      node (U-turns present? which lanes fan where?). That is the engine default we do not model.
- [x] **Tool**: Apply automatically Off, place one, Smart Lanes tool, click the east slip node: chip
      "Slip-lane junction: diverge, 2 lanes" / "2 -> 2 + 2 slip, <n> lane connections"; log `PICK ...
      node_kind=slip`. Apply to roundabout: "Not a roundabout: use Apply to junction", nothing written.
      Reset: "Reset not available here (no Apply yet)". Apply to junction: `APPLY src=tool kind=slip`,
      `WRITE src=tool kind=slip node=.. success=true`, `VERIFY src=tool kind=slip node=.. same=1
      nodes=1`; the overlay redraws. Reset: `RESET mode=snapshot kind=slip node=.. conns=<engine count>`,
      the Crossing Tool shows the engine's fan-out again. Apply again: smart lanes again.
- [x] **Traffic**: run a few minutes with traffic from all arms: right turns use the slip lanes,
      nobody stops at the gore, merges give way into the kerb lane, nothing gets stuck at the side
      road's node (it has a merge and a diverge).
- [x] Town large main road (3 lanes each way): diverge `3_->_3_+_2_slip` (kerb lane shared), no errors.
- [x] **Left-hand traffic** save (Traffic side Left-hand): the same lines with `side=left`; Crossing
      Tool shows the mirror image (the kerb is on the left). This checks the driving-side detection.
- [x] Roundabout Interchange: the highway gore nodes (off-ramp leaving, on-ramp joining) log
      `kind=slip case=A`; ring junctions still log the ring lines. Splitter split nodes: no lines.
- [x] A hand-built one-way slip lane between two two-way roads (right turn): both ends get
      `kind=slip`. A plain crossroads / T of two-way roads: no `kind=slip` lines.

## H. Lane status badge (PLAN.md "Lane status badge")
Setup: Apply automatically **Off**; a Better Roundabouts 4-lane ring with medium arms (4 arms), a
Channelized Junction T, a plain crossroads.
- [x] Toolbar: a second chip under the status chip (own row, separator above) reading "Lane status"
      while nothing is selected. Not clipped? **Colour**: green for Smart lanes, amber for Custom /
      partial, or grey everywhere (the disabled-button rule wins; note which). Hover shows the tooltip.
- [x] Click a ring junction: badge "Game default", log `PICK ... badge=default`.
- [x] Apply to junction: after `VERIFY src=tool ... same=1` the badge turns "Smart lanes" (green?).
- [x] Click the ring between junctions: "Smart lanes on 1 of 4 junctions", `PICK ... badge=partial`.
      Apply to roundabout -> "Smart lanes"; Reset -> "Game default" (each after its VERIFY).
- [x] With the ring junction still selected, change one connection with the **Crossing Tool**, come
      back to Smart Lanes (or keep it open in the background): within about half a second the badge
      reads "Custom lanes".
- [x] Hover (not click) a junction / the ring: the cursor tooltip has a third line "Lanes: ...".
- [x] Channelized T east slip node (Apply automatically Off): "Custom" (`badge=custom`), after
      Apply to junction "Smart lanes". Its centre node and the crossroads: "Not handled" (`badge=na`).
- [x] Vanilla 1-lane roundabout junction: "Smart lanes (= game default)" when it has one entry lane.
- [x] Tram-street ring: the badge ignores tram connections (Game default before, Smart lanes after Apply).
- [x] Any stutter while hovering over a big ring (the badge is recomputed on hover changes, cached)?

## One-way arrows in lane tools (2026-10-08)

- [x] Smart Lanes tool open: white one-way arrows on one-way streets (as in the street builder).
- [x] Native Crossing Tool open: same arrows; log has `PROBE oneway=patched` (at load) and
      `PROBE oneway=crossing_tool` (first time the Crossing Tool renders).
- [x] With a map layer picked (e.g. traffic) the layer shows instead, as in the street builder.
- [x] Other construction tools (bulldozer, track builder) unchanged: no arrows.
- [x] (not the case: patched at game load) If the Crossing Tool shows no arrows until Smart Lanes was opened once, the script loads lazily (note it).

## Greyed-out buttons (2026-10-08)

Apply / Reset are enabled only when the click would change something (`sl_toolcore` `C.actions`,
read by each button's `checkEnabledFn` every menu step).
- [ ] Nothing selected: all three buttons grey.
- [ ] Vanilla roundabout junction (game default): both Apply enabled, Reset grey.
- [ ] Apply to junction: all grey for ~half a second (write pending), then Apply to junction grey,
      Apply to roundabout and Reset enabled.
- [ ] Apply to roundabout, then select the ring: only Reset enabled. Reset: back to Apply only.
- [ ] Change a junction with the Crossing Tool, reopen Smart Lanes on it: Reset enabled (Custom).
- [ ] Slip junction: Apply enabled, Reset grey until an Apply; after Reset, Reset grey again.
- [ ] Crossroads / nothing handled: all grey.
- [ ] Do the button tooltips still show on a greyed button? (note it; the text says when it greys)
- [ ] No flicker of the buttons while hovering around with a selection.
