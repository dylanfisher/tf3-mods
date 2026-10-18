# square_smart_lanes: in-game test checklist (Phase 1)

Setup: `make link` (staging), new free game (right-hand traffic), mods: Smart Lanes (defaults) and
Better Roundabouts (`square_roundabouts`). No other lane mods. Keep `stdout.txt` open:
`tail -f ~/Library/Application\ Support/Steam/userdata/<steamid>/3493540/local/crash_dump/stdout.txt | grep SQRL`

Expected log per roundabout: one `[SQRL] APPLY ...` line per changed junction, one `WRITE ... success=true`,
then `VERIFY ... same=<n> nodes=<n>`. Anything with `ERROR` or `success=false`: copy the lines into
`plans/square_smart_lanes/` and stop.

**First open check (rev 4, before release): section FK checks 1-2**. findings.md (2026-10-12, a hand edit in the
base Crossing window) says an unlocked right turn does NOT give way, so the setting now has three values: Off /
When safe (the curb turn is unlocked only in phases where nothing green conflicts) / Always (every phase; the
default since 2026-10-12, user decision). Check that a turner freed "When safe" never meets green traffic in its
exit lane or green pedestrians, and compare with Always. If Always jams or drives through traffic: default When safe
or Off (mod.json `defaultIndex` 1 / 0, `Rules.DEFAULTS.freeTurn` 2 / 1; see FK "If it fails").

## 1. Does the write work?
- [x] Place a Better Roundabouts **2-lane ring, medium arms, 4 arms**. Log: 4 `APPLY` (turbo=true,
      before=6 after=5), `WRITE success=true`, `VERIFY same=4 nodes=4`.
- [x] Open the **Crossing Tool** on one ring junction: outer ring lane only turns into the arm (curb
      exit lane), inner ring lane goes straight or into the second exit lane; arm curb lane -> outer ring
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
      (Since 2026-10-13 the whole ring is planned: see check WR below.)
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
- [x] **Crossing Tool** on the east (diverge) node: westbound curb lane -> both slip lanes and the
      curb through lane; second lane -> second through lane only; eastbound lanes straight 1:1; no
      U-turns, no crossing lines. West (merge) node: slip lanes -> the curb lane only, through lanes
      1:1. Side road node: northbound + slip -> curb lane; southbound curb lane -> slip and straight.
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
      nobody stops at the gore, merges give way into the curb lane, nothing gets stuck at the side
      road's node (it has a merge and a diverge).
- [x] Town large main road (3 lanes each way): diverge `3_->_3_+_2_slip` (curb lane shared), no errors.
- [x] **Left-hand traffic** save (Traffic side Left-hand): the same lines with `side=left`; Crossing
      Tool shows the mirror image (the curb is on the left). This checks the driving-side detection.
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

## H2. Readable status texts (rev 5, 2026-10-13)

Prompted by a player question (a bus-lane junction read "not handled (bus_lane)"). Check in game, English and one
other language (de or ru: longer text), that every text fits the toolbar chip and the cursor tooltip:

- [ ] A junction with a bus lane (Bus Lane Tool on one arm): handled since the bus-lane change (section BL): detail
      "16 lane connections, bus lanes kept as they are". A roundabout whose ring has a bus lane: "not handled: the
      ring has a bus lane". A 5-road junction: "not handled: 5 roads meet (at most 4)".
- [ ] A ring junction where two roads join: "not handled: two or more roads join here".
- [ ] A slip node of the Channelized Junction: head "Slip lane leaving the road, 2 lanes" (or joining), detail
      "2 lanes in: 2 straight on, 1 into the slip lane, …"; before Apply the badge reads "Game or custom lanes".
- [ ] A crossroads whose lights were switched off after Apply: badge "Custom lanes"; the badge tooltip names the
      lights as a cause; Apply to junction gives it smart lanes.
- [ ] 2-lane ring with 1-lane exits, Apply to roundabout: "… applied to 4 junctions; no exit-only outer lane: an
      exit has only one lane".
- [ ] No head shows a node or ring id any more (they stay in the PICK log lines).
- [ ] Do town-built streets reach the automatic pass? handleBuild returns unless `playerInitiated` (p[4]) is true.
      Let a town grow a street onto a Smart Lanes roundabout arm or crossroads (Apply automatically On) and look for a
      SUMMARY / APPLY line at that moment. Yes: the Notes may mention town growth again; no: towns never trigger it.
- [ ] Game-default model of a bent T-junction: node 48723 (new desert game, 2026-10-13, never written by Smart
      Lanes, most likely a town street) reads `badge=custom` with the game's own lanes: side road 24454 (1+1
      lanes) at 134 deg, main road 28936 (2+2) at 41 deg and 80137 (2+2) at -95 deg (136 deg bend). The game
      leaves 80137 lane 2 without any connection (AUDIT `dead:80137`) and turns 28936 lane 2 into both lanes of
      80137. CONN lines in `2026-10-13_2037_sqrl-sqsg`. Decide whether X.defaultConns / X.isDefault should
      model it (then the badge says Game default and Reset gives back these lanes). Until then a T-junction
      that does not match the model reads "Game or custom lanes", never the gold "Custom lanes".
- [ ] Toolbar: [Apply | Reset] in one row (German "Anwenden | Zurücksetzen" not clipped); under them the
      selection, the result and the lane status as plain text (no grey box, left-aligned, readable on the
      panel); "Smart lanes" blue, "Custom lanes" / partial gold. Hovering the text still shows its tooltip.
      If the stylesheet does not take, the boxes stay grey: note which rule failed (no crash expected).
      Plain text, left-aligned, blue / gold: seen in game 2026-10-13 (user screenshots 1:40-1:43 PM).
- [ ] Long lines wrap inside the panel (textAutoWrap, 280 px): a 4-lane ring after Apply ("... applied to 4
      junctions; no exit-only outer lane: ..."), a selected ring ("Apply or Reset: the whole roundabout; ..."),
      a slip node ("3 lanes in: 3 straight on, 2 into the slip lane, 8 lane connections"). Before: cut off.
- [ ] Apply with the roundabout selected (click between junctions) sets all its junctions; with one ring
      junction selected only that one; a street and a Shift+click selection as before.

## One-way arrows in lane tools (2026-10-08)

- [x] Smart Lanes tool open: white one-way arrows on one-way streets (as in the street builder).
- [x] Native Crossing Tool open: same arrows; log has `PROBE oneway=patched` (at load) and
      `PROBE oneway=crossing_tool` (first time the Crossing Tool renders).
- [x] With a map layer picked (e.g. traffic) the layer shows instead, as in the street builder.
- [x] Other construction tools (bulldozer, track builder) unchanged: no arrows.
- [x] (not the case: patched at game load) If the Crossing Tool shows no arrows until Smart Lanes was opened once, the script loads lazily (note it).

## Hidden buttons / Toolbar rows (2026-10-08 greyed; hidden since 2026-10-14, rev 8; rows + grayed with a reason since rev 8 v2; hidden when nothing to do + small buttons since rev 8 v3, 2026-10-16)

Rev 8 v3 (user 2026-10-16, PLAN.md "Toolbar: rows, hidden when there is nothing to do"): row 1 Smart lanes | Reset,
each only where a click would change something (both hidden: no row), grayed only while a change lands; row 2 Smart
lights | Re-time only at a junction with a standing light, grayed with their reason; Record traffic at a real junction
(3 roads or more) or roundabout. Every action button in the small look of the Keep timing adjusted toggle. Nothing
selected: no rows.
- [ ] Nothing selected: no buttons, no empty rows or stray separator lines; "Nothing selected" + the pick hint.
- [ ] **Small buttons:** Smart lanes, Reset, Smart lights, Re-time and Record traffic about as tall as the Yes / No of
      Keep timing adjusted (no longer the 32 px squares), labels not clipped, the look of a normal (not "selected")
      button or at least the same as before. Click each one twice in a row: both clicks act (the result line changes;
      Record traffic starts, then stops). If a button shows highlighted as "selected" or a second click does nothing,
      note it (fallback: drop `numbers = { 1 }` in sl_tool.script.lua actionButton).
- [ ] Vanilla roundabout junction (game default): Smart lanes shown, no Reset (the row has one button, left-aligned, no
      gap where Reset was). Lane status "Game default".
- [ ] Smart lanes: it grays for ~half a second ("A write is still landing"; hover its label: the tooltip starts
      "Grayed out: A write is still landing" above the button's own text. **Answers:** does a tooltip inside a grayed
      toolbar button show at all?), then it disappears and Reset appears. Note how the row re-lays (the user accepted
      the jump, 2026-10-16).
- [ ] Apply on the ring, then select the ring: only Reset. Reset: only Smart lanes.
- [ ] Change a junction with the Crossing Tool, reopen Smart Lanes on it: Reset shown (Custom).
- [ ] Slip junction: Smart lanes shown, no Reset until a Smart lanes click there.
- [ ] 1-lane crossroads (smart = game default) / not handled (5 roads): no first row at all; the badge and the detail
      line say why ("Smart lanes = game default (one car lane per road)", "not handled: <reason>", "nothing to change
      here").
- [ ] A bend or lane drop of one road (2 roads, "no junction here"): no Smart lanes / Reset row unless it is a handled
      lane drop, and never Record traffic. A real junction without Smart Lanes applied (a game-default crossroads):
      Record traffic shown.
- [ ] Unlit crossroads: no second row at all. Lit crossroads: the second row appears (Smart lights | Re-time), both
      fit in de / ru / fr / es / pt_BR ("Semáforos inteligentes | Reajustar tiempos" is the longest).
- [ ] Lit junction that is no crossroads / T (a 5-arm junction, a slip node with a light): Smart lights grayed "Only at
      a crossroads or T-junction", Re-time enabled.
- [ ] No flicker of the buttons while hovering around with a selection (states follow the selection only).

## I. Traffic lights (rev 4, setting "No lights at roundabouts and ramps")
Year 1950 or later (the game adds automatic lights from then; `traffic_light_config.res.lua`). The
lights go through `createTrafficLightProposal(node, config:clone(), NO)`, the call the base node
window's "None" button makes (`double_slip_switch.tl:56,489`). Unverified in game until this section is done.
1. **Roundabout, setting On:** place a 4-arm roundabout with large arms. stdout.txt shows
   `[SQRL] LIGHTS src=auto node=... before=auto light=... to=off` per arm junction and then
   `VERIFY kind=lights off=N nodes=N`. No lights at the entries; the Traffic Light Tool shows them off.
2. **Channelized Junction:** the centre crossing keeps the game's lights; the nodes where the
   slip lanes leave and rejoin the arms have none (LIGHTS lines for them only).
3. **Parclo / Diamond:** ramp merge and diverge nodes on the highway have none; the ramp ends on
   the cross road (ordinary crossroads) keep the game's choice.
4. **Hamburger with "Road + traffic lights":** the centre crossings keep their lights (skip nodes).
5. **Tool:** on a roundabout built before rev 4 with lights, Apply to roundabout switches them off
   (LIGHTS src=tool, VERIFY kind=lights to=off); Reset gives AUTO back (src=reset, to=auto) and
   the game re-adds them.
6. **Setting Off:** a new roundabout keeps the game's lights; no LIGHTS lines.
7. **No loop:** after the light commands, no further APPLY/WRITE lines for the same nodes.
8. **Traffic:** cars on the slip lanes and ramps merge without stopping; note who gives way at
   a slip-lane rejoin without lights (findings.md has nothing on it yet).

## J. Tangential ramps (rev 4, 2026-10-11)
In game 2026-10-11 (Junction test, all types): every parclo / Parclo 2 / Diamond / Roundabout Interchange gore was
`SKIP kind=slip reason=ambiguous` (the ramp's direction at the gore equals the highway's), so ramps kept the game's
lanes. Now the far ends of the segments decide (`APPLY kind=slip ... split=far`), then the lane count (`split=lanes`).
1. Place a Parclo: expect `APPLY kind=slip ... shape=diverge|merge ... split=far` at each gore, `VERIFY kind=slip same=N`
   and LIGHTS lines for them; no `ambiguous` for the gores. With the Crossing Tool: the through lanes go straight on,
   the curb lane alone feeds the off-ramp, the on-ramp merges into the curb lane.
2. Drive: no car crosses lanes at a gore; cars bound for the ramp use the curb lane.
3. Remaining `ambiguous` (log the node and what it is) and `branch_turn` (ramp ends meeting the cross road at a right
   angle: an ordinary T, left alone on purpose).

## K. Crossroads and T-junctions (rev 4, sl_cross.lua, 2026-10-11)
Best-guess rule, not yet checked in game: per approach, exits ordered curb turn -> straight -> far turn; 1 lane goes
everywhere, 2 lanes share (curb: turn + straight, far: straight + turn), 3+ lanes give each turn its own lane (curb
lane turn only; with 3 lanes and 3 exits the far lane also goes straight). Curb turns enter the exit's curb lanes,
straight and far turns its far lanes, so a 3-lane road's straight traffic leaves the exit's curb lane to the side road.
Crossroads keep their lights. Stress Test → Crossing test (21 crossings) is the bench.
1. Build the Crossing test: expect `APPLY kind=slip ... shape=crossroads|t_junction case=X ... lanes=<seg>:k|s|sf;...`
   for every crossing and T, `VERIFY kind=slip same=N`, no LIGHTS lines for them, no ERROR.
2. Smart Lanes tool on `x11` (3x3): head "Crossroads, 3 lanes", badge Smart lanes. Crossing Tool view: curb lane
   arrows right only, middle straight, far lane straight + left.
3. Grow the towns and run at speed 4: no queues from turning cars blocking straight lanes; no car stuck in a lane
   that cannot reach its exit. Note any crossing (id) where traffic jams worse than the game default (tool Reset to
   compare: it restores the lanes from before the first Apply).
4. Left-hand traffic save: the same mirrored (curb lane turns left only).
5. Reset on a crossroads writes the game-default MODEL (`RESET mode=model kind=slip`; sl_cross X.defaultConns: curb lane
   turns into every lane of its exit + straight, far lane likewise, straight lane to lane; from the 2x2 town dump and
   the 36 of fresh 3x3s). Check: build a crossroads with Apply automatically Off, pick it: badge "Game default" (else
   the model is wrong there: send the CONN lines). Then Apply, Reset: badge "Game default" again. T-junctions and
   unequal lane counts are extrapolated; check one of each. Since 2026-10-12 the badge compares per movement
   (sl_cross X.isDefault: connection count + exit lanes per approach > exit; straight movements still lane to lane,
   as in 331872's log), because the game gives some 3x3
   approaches two-lane turns (Showcase g3b node 331872 read "Custom" before). Showcase g3b (ab=game): badge
   "Game default", Reset says "already set" and writes nothing.
6. One-way roads (sl_slip hands them over instead of skipping `branch_turn` / `far_side_branch` /
   `two_branches_one_direction` / `main_bend`): Diamond and Parclo ramp ends at the cross road, a divided road
   crossing a road, a one-way street crossing / ending at a two-way street. Expect `case=X`; the off-ramp never
   connects straight back to the on-ramp (turns over 135 degrees are no exits). A ramp (one-way, no sidewalk) never connects to another ramp at the
   same junction unless it has no other exit: the parclo off-ramp must not run straight across onto the on-ramp (in game
   2026-10-11); a one-way town street (sidewalks) still goes straight through. Splitter split nodes stay unlogged
   (`mixed_one_way`); one-way-only junctions are skipped `no_two_way`.

## L. Ramp keeps its own lane at a tight merge (rev 4, 2026-10-11)
In game 2026-10-11 (node 17156: a 3-lane road + 1-lane loop ramp -> 3 lanes): the ramp shared the curb lane and queued.
Now a merge with T + B > O where the through road keeps two or more lanes (O - B >= 2) gives the branch its own curb
lanes and folds the through lanes among themselves (`Slip.pairs("merge", 3, 1, 3)` = q1>o1, p1+p2>o2, p3>o3).
2 + 1 -> 2 is unchanged (the ramp gives way into the curb lane).
1. Re-apply node 17156 (Smart Lanes tool, Apply to junction): Crossing Tool view: the ramp lane alone into the curb
   lane; the road's two curb-side lanes both into the middle lane.
2. Run traffic: the loop ramp no longer queues; watch whether the road's own lanes now queue before the merge.

### L2. Look-ahead for the own-lane merge (PHASE7.md step 1, sl_walk.lua)
The own-lane merge above now depends on the roads around the merge node (`Slip.mergeLook`). Smart Lanes walks the
through road back and the out road on through plain nodes (2 road segments; at most 400 m and 12 segments each way,
stopping at a junction, dead end, missing node or loop) and decides, first rule that applies:
1. the out road loses a lane within 150 m: give way (`why=drop_ahead`);
2. the through road had at most O - B lanes somewhere on the walk (its curb lane was added nearby): own lane
   (`why=lane_added`);
3. the through road's previous junction (3+ road segments) is under 80 m back: give way (`why=junction_close`);
4. the through road had all T lanes the whole walk: give way (`why=through_road`), unless the out road's next junction
   (within 400 m) has a road leaving on the curb side (an off-ramp, slip lane or curb-side turn; where the out road
   ends there, e.g. a T, any curb-side turn; either branch of a symmetric fork): own lane (`why=exit_ahead`);
5. otherwise own lane (`why=lane_added`).
The APPLY line (automatic pass and tool) carries `merge=own_lane|give_way why=...` for every merge whose counts allow
the own lane (T + B > O, O - B >= 2); other merges have no `merge=` field.
1. Node 17156 again (3-lane road + loop ramp): Apply to junction; the log says which rule fired. In a cloverleaf with
   the next loop off-ramp within 400 m expect `merge=own_lane why=exit_ahead` (ramp alone in the curb lane); a loop
   ramp onto a long 3-lane road with no exit nearby expects `why=through_road` (ramp shares the curb lane).
2. Build a 2-lane one-way road, widen it to 3 lanes 50-100 m before an on-ramp node (a plain node where the lane count
   changes), 3 lanes after: `why=lane_added`, the ramp keeps its own lane, the road's two curb-side lanes fold into
   the middle one.
3. Put a side road 50 m before the on-ramp node on a 3-lane road: `why=junction_close`, give way.
4. Narrow the out road from 3 to 2 lanes 100 m after the merge: `why=drop_ahead`, give way; move the narrowing to
   200+ m: the previous decision comes back (re-apply with the tool).
5. Left-hand traffic: repeat 2 and 4 on a left-hand-traffic map; the same `why=` values, mirrored lanes.
6. Run traffic on each: give-way merges should not queue the ramp badly on a free-flowing road; own-lane merges
   should not queue the road's lanes before the merge. Note any case where the decision looks wrong.

## M. Lane drops and gains (rev 4, PHASE7.md step 2, sl_slip case "D")
Plain nodes (exactly two road segments) where a travel direction's lane count changes were left with the game's
connections. Now (`Slip.classify` -> `classifyDrop`): per travel direction lanes are matched from the far (median)
side; extra incoming curb lanes fold into the curb-most continuing lane (the curb lane ends), extra outgoing curb
lanes are fed by the curb lane (`Slip.pairs("straight")`). A direction whose count stays is matched lane to lane.
Log: `APPLY kind=drop node=.. shape=lane_drop|lane_gain|lane_drop+gain case=D side=.. side_from=two_way|walk
lanes=3_->_2;_2_->_3`. Lights are never touched there. Nodes where nothing changes stay unlogged (`roads_2`).
Driving side: two two-way roads: their lane layout (disagreeing: `SKIP kind=drop reason=mixed_sides`). Two one-way
roads (one in, one out): the first two-way road met by a bounded walk (400 m / 12 segments each way, Walk.follow) or
at the junction it stops at; none: left alone (`no_side`, unlogged). A one-way loop through the node (a ring the ring
rules refused) is left alone (`loop`). A two-way road going on as a one-way road (`one_way_end`) and one-way roads
against each other (`one_way_clash`) are left alone: the game's connections for the dead direction are unknown. Bus
lanes (rev 5, section BL): the car lanes count (a bus lane starting is a drop for cars), the bus connections are
kept. A road U-turn among the node's connections (a turnaround): `SKIP kind=drop
reason=u_turn`, nothing written. Tram connections kept. Reset: no model of the game's connections at a lane
drop yet, so the tool's Reset restores the snapshot from before the first Apply (as at slip nodes). A snapshot that
names a segment no longer at the node (the road was rebuilt since the Apply) is dropped: `RESET mode=stale`, "Reset
not available here", nothing written (crash rule 3).
1. Build a 2-way road, then upgrade a middle stretch from medium (2 + 2) to large (3 + 3): at both ends expect
   `APPLY kind=drop shape=lane_drop+gain case=D side=right side_from=two_way`, `VERIFY kind=slip same=1`, no LIGHTS
   line. Crossing Tool view: the ending curb lane and its neighbour both into the curb lane of the narrow road; the
   narrow road's curb lane into both curb lanes of the wide road; the far lanes straight on. No crossing.
2. Before applying (Apply automatically Off, or a road built before the mod), pick such a node with the Smart Lanes
   tool: head "Lane drop and gain, 3 lanes", badge "Game or custom lanes" (rev 5; "Custom" before) (or "Smart lanes" if the game already does the same:
   then send the CONN lines, the game default might be worth a model). Apply, Reset: the old connections come back
   (`RESET mode=snapshot kind=slip`).
3. One-way roads: a 3-lane one-way road narrowing to 2 near a two-way road (e.g. a highway carriageway that starts at
   a dual-carriageway split): `side_from=walk`. Far from any two-way road (a long highway): no APPLY (left alone).
4. Asymmetric widths (a road with 2 lanes one way and 3 the other meeting 2 + 2): `shape=lane_drop` (one direction
   matched lane to lane).
5. Drive: traffic in the ending curb lane merges into the next lane at the node; no vehicle switches across two
   lanes there; at a gain both curb lanes fill. Watch for queues at the drop that the game default did not have
   (compare with Reset).
6. Left-hand traffic map: repeat 1 and 3; the curb lane on the left ends, `side=left`.
7. Merge look-ahead consistency (L2): a lane drop within 150 m after an on-ramp still gives `why=drop_ahead`.
8. Stale Reset: Apply at a lane drop with the tool, rebuild one of its two roads (another road style with the same
   lanes), pick the node again: Reset is hidden (greyed before 2026-10-14); no crash.

## N. Exit-only curb lane before off-ramps; remembered driving side (rev 4, PHASE7.md step 3)
Diverge rule (`Slip.pairs("diverge", N, T, B, exitOnly)`): with N <= T the curb lane fed the branch AND went
straight. Now, when the counts allow it (`Slip.exitLanes`: N <= T and through traffic keeps 2+ lanes, so N >= 3;
E = min(B, N - 2) exit lanes) and the look-ahead (`Slip.divergeLook`) agrees, the E curb lanes feed only the branch
(extra branch lanes fan from the last of them) and the rest go straight aligned from the median side; a curb-side
through lane left unfed is fed by the next lane (no crossing). N > T is unchanged (the curb lanes are the branch's
by the counts already: 3 -> 2 + 1, 4 -> 3 + 1), and so is 2 -> 2 + 1 (shared). The look-ahead walks the main road
back (400 m / 12 segments, Walk.follow), first rule that applies:
1. the road had at most N - E lanes somewhere on the walk (the exit lane was added nearby, an auxiliary lane):
   exit-only (`why=lane_added`);
2. the road's previous junction (3+ road segments) is under 80 m back: shared (`why=junction_close`; traffic that
   entered there in the curb lane has no room to move out of it);
3. otherwise exit-only (`why=through_road`; `why=lane_added` when some but not all exit lanes were added).
The APPLY line carries `diverge=exit_only|shared why=...` for every diverge whose counts allow exit-only lanes; with a
merge decision on the same node (Channelized Junction side node): `diverge=.. merge=.. why=<diverge>,<merge>`.
Remembered driving side: every classified node with a two-way road (and the lane-drop walk's finds) remembers an
ANCHOR, that two-way segment and its node (module state; whether the Lua states are rebuilt when another save is
loaded in the same session is not verified, so no bare side is kept). A one-way lane drop with no two-way road within
the walk re-reads the side at the anchor in the current world (`Slip.rememberedSide(world)`: node exists, segment
still attached, two-way there, clear side) and uses it: `APPLY kind=drop ... side_from=remembered`. An anchor that is
gone, detached or now one-way is dropped and the drop is left alone (`no_side`) until a two-way road is read again;
in another save the same ids name that map's own road, so its side is that map's.
1. A 3-lane one-way highway (long, no junction 80 m before), a 1-lane off-ramp, 3 lanes on: `kind=slip case=A
   shape=diverge diverge=exit_only why=through_road`. Crossing Tool view: curb lane only into the ramp; the middle lane
   into the two curb-side through lanes, the far lane straight. Drive: through traffic leaves the curb lane before
   the gore; no vehicle crosses lanes at the node.
2. Same highway, an on-ramp merge node 50 m before the off-ramp (a weave): `diverge=shared why=junction_close`, the
   curb lane into the ramp and straight on.
3. Widen a 2-lane one-way road to 3 lanes 60 m before an off-ramp (and keep the on-ramp 50 m before that): `why=
   lane_added`, exit-only.
4. Town: a large (3 + 3) road with a Channelized Junction (2-lane slip lanes): the diverge node gets `diverge=
   exit_only` (curb lane into both slip lanes); with a crossroads under 80 m behind it: `shared`. A medium road
   (2 + 2): no `diverge=` field, unchanged.
5. A 4-lane road with a 2-lane exit (4 -> 4 + 2): two exit-only lanes (`why=through_road`).
6. Left exit (one-way, ramp on the far side): exit-only lane on the left.
7. Left-hand traffic: repeat 1, 2 and 4; same `why=` values, mirrored lanes.
8. Remembered side: in a fresh game, first build a lane drop (3 -> 2) on a long one-way highway far from any two-way
   road: no APPLY. Then build or Apply anything on a two-way road, then rebuild / Apply the lane drop: `side_from=
   remembered`, the curb lane ends. Bulldoze that two-way road and rebuild the lane drop: left alone again (the
   anchor is gone) unless another two-way road was read since. Load another save (left-hand traffic map) without
   restarting: the first lone drop there must never be wired right-handed (left alone, or `side=left` when the anchor
   ids happen to name a two-way road there). Note whether the remembered side survives the load at all (tells whether
   the Lua states are rebuilt; add the answer to docs/findings.md).
9. Traffic: watch exit-only nodes under load for queues in the remaining through lanes that the shared curb lane
   did not have (compare with Reset); note any case where exit-only looks wrong.

## O. Tool: click a street to select its junctions (rev 4, PHASE7.md step 4, sl_street.lua)
**Changed 2026-10-11 (user decision "Ends only, Shift extends", after a mid-road click selected 6 junctions across
two big constructions):** a plain click (and the hover) selects only the handled junctions at the clicked segment's
two ends: through plain nodes to the FIRST junction (3+ road segments) each way, included when handled, plus the
handled plain nodes between (lane drops, at most 4: stop `max_drops`); stop `end` at that junction (`Street.walk`
ends mode, `PICK target=street:<seg> mode=ends`). Shift+click follows the street as described below
(`target=street+:<seg> mode=follow`), with the caps now 10 junctions and 1 km. Shift = the game's "(Hold)" modifier
`IA_PRECISION_MODE` (Shift by default), read at the click with `api.gui.inputAction.modifierOnlyActionIsActive`
in a pcall, as Bulk Bulldozer reads it at the LMB press; unreadable = a plain click. The hover never reads Shift: it
always shows what a plain click selects (the status detail / cursor tooltip says "Shift+click: add a junction or road",
step 5b, formerly "Shift+click to follow the street further"); a Shift-selected street is not reused for the hover. `STREET op=.. mode=ends|follow`.
0. Shift checks: click the middle of a segment between two crossroads with a lane drop between: head "Street: 3
   junctions" (the two crossroads + the drop), `mode=ends stops=end,end`. Shift+click the same segment: more
   junctions (`mode=follow`), at most 10, at most 1 km. Click near a big construction (Channelized Junction, parclo):
   only the two nearest junctions. Note whether Shift is detected (if a Shift+click logs `mode=ends`, the modifier
   is not readable from onSelect: report it).
A click (or hover) in the middle of an ordinary segment (not near its ends: those still promote to the node; not a
ring segment: that still selects the roundabout) selects the street through it. The walk (`Street.walk`) goes both
ways, the two ends in turn: through plain nodes (two road segments, whatever their lanes: a lane drop is part of the
street) and through junctions on the leaving segment with the smallest turn (tangents; two within 5 degrees told
apart by their far ends), at most 30 degrees, with the same road lanes per travel direction (one-way-ness
included). Stops: `turn`, `fork` (two ways on within 5 degrees at the node and at their far ends), `lanes`,
`dead_end`, `ring` (a roundabout junction ends the street and is not part of it), `loop`, `max_dist` (1 km; was 3 km), `max_junctions` (10; was 60), `max_nodes` (400), `no_node` / `no_seg`. Junctions = nodes
where `Slip.classify` says `slip` (cases A, B, X, D); a junction where the street stops belongs to it. No handled
junction: nothing selected (as before).
Log: `PICK target=street:<seg> junctions=.. segs=.. dist=.. stops=<end b>,<end a> nodes=<ids> badge=..` (no CONN
dump); Apply to junction / Reset: `STREET op=apply|reset street=<seg> junctions=.. batches=..`, then per node `APPLY
src=tool scope=street street=<seg> kind=slip|drop node=..` or `RESET mode=model|snapshot|unavailable|stale
scope=street ...` or `SKIP src=tool scope=street ... reason=gone|no_config|ring|<classify reason>|conns`, per batch
(at most 40 nodes, one proposal, one batch per frame) `WRITE src=tool|reset scope=street street=<seg> batch=i/n
nodes=.. success=..` and 30 frames later `VERIFY ... scope=street ... same=.. nodes=..`.
1. Town street with a crossroads, a Channelized Junction (slip lanes), a lane drop (large -> medium) and a T at its
   end. Click the middle of a segment: head "Street: N junctions", markers on every junction, the street's segments
   highlighted, and (step 5b, section S) the lane arrows of every junction. The PICK line lists the expected nodes and
   `stops=` reasons. Hover elsewhere on the street: same street in the cursor tooltip.
2. The street turns 90 degrees at a junction: the walk stops there (`turn`), that junction included. A junction
   where the continuing road is wider/narrower: stops (`lanes`). A street running into a roundabout: stops before
   it (`ring`), the roundabout untouched by Apply.
3. Lane status: fresh game connections: "Game or custom lanes" (rev 5; "Custom" before) (slip / drop junctions have no game-default model) or "Smart lanes
   on k of N junctions"; after Apply: "Smart lanes"; pick one crossroads, Reset it, click the street again: partial.
   A street of crossroads only: "Game default" / "Custom lanes".
4. Buttons (one Apply since rev 6; hidden instead of greyed since 2026-10-14): Apply shown while any junction is not
   smart; Reset when a crossroads differs from the game default or a slip / drop junction differs from its snapshot.
   The shown ones grey while batches are being written.
5. Apply on a street (Shift+click; with the 10-junction cap one batch: `batch=1/1`; batches of 40 are covered by the
   unit tests): WRITE lines on consecutive frames, every VERIFY `same` = `nodes`; no hitch, no crash. Traffic lights:
   slip junctions lose theirs with "No lights at roundabouts and ramps" On; crossroads and lane drops keep theirs.
6. Crash checks: select a street, bulldoze one of its junctions (or rebuild a segment) BEFORE pressing Apply: `SKIP
   ... reason=gone` (or the node re-planned from the new roads), the rest written, no crash. Select, Apply, rebuild
   the narrow side of the lane drop, Reset: `RESET mode=stale` for that node, the others reset.
7. Reset: crossroads back to the game default (`mode=model`), slip / drop junctions to their pre-Apply lanes
   (`mode=snapshot`), never-applied ones `mode=unavailable` and left alone.
8. Performance: hover along a long one-way street (ring search per junction) and a long avenue; SQPERF `hover` /
   `select` sections stay in the low ms.
   Moving the cursor along the selected street (or the street just hovered) reuses that street (no new walk until
   the next 30-frame re-read); check the SQPERF `hover` max while sweeping along a long avenue.
   A capped plain-click street (`stops=` with `max_drops` / `max_dist` / `max_nodes`) is reused only on the
   segment it was resolved from (the caps count from there), so the tooltip always matches a click.
9. Close the tool (Esc / another tool) right after Apply on a street (with 10 junctions at most one batch, so
   mostly unit-tested now): `SKIP ... reason=tool_closed batches=..` for the unsent batches, the sent ones still WRITE / land, no result text when the tool is reopened,
   buttons back within a second. Select another junction while the batches are written: its status chip shows no
   street result; its Apply / Reset stay greyed (or hidden, where they would change nothing) until the street job is done.

## Q. SUMMARY line per automatic job (rev 4, PHASE7.md step 6)

The automatic pass logs one line per processed build job, after its APPLY / SKIP lines and when its proposals are
sent:

`[SQRL] SUMMARY job=<seq> nodes=<job nodes> rings=<rings found> ring=<applied>/<same>/<skipped> slip=<A/B nodes
sent> cross=<crossroads / T nodes sent> drop=<lane drop / gain nodes sent> same=<already right> skip=<total>
skips=<reason:count,...>`

- `skips=` lists the skip reasons (ring and other nodes together) most frequent first, ties by name, each under its
  first word (`lights:2>5` counts as `lights`, `no_strategy:subset=..` as `no_strategy`); `-` without skips. Kept
  under the 200-character value cap: reasons past it become `+N`.
- Nodes the write layer refuses (phases that cannot be re-pointed, no config, read-only strategy) move from their
  applied count to `skip`; whether the proposal landed is still the WRITE / VERIFY lines' job.
- Builds that met nothing handled (plain road: no ring, no slip / crossing / drop candidate) log no SUMMARY, so
  ordinary road building stays quiet.

Checks:
1. Place a 4-lane roundabout: `SUMMARY ... rings=1 ring=4/0/0 ... skip=0 skips=-`. Build over it again (upgrade a
   ring segment to the same type): `ring=0/n/0 same=n`.
2. Place the Channelized Junction: `slip=3 cross=1` (the centre T by the crossing rule). With traffic light phases
   on the centre that cannot be re-pointed: `cross=0 skip=1 skips=lights:1`.
3. A road narrowing large -> medium: `drop=1`. A straight piece of plain road: no SUMMARY line.
4. The Stress Test Junction / Crossing test (Smart Lanes enabled): one SUMMARY per built junction job; compare the
   counts with the bench's own summary line, and note the top `skips=` reasons for the rule review.

## R. Crossroads: turns a slip lane serves are left to it; far lane shares straight (rev 4, sl_cross X.bypasses)

In game 2026-10-11 (Channelized X, square_roundabouts): the centre's curb lanes still turned right through the
traffic lights, so right turners queued there and ignored the corner slip lanes. Now, at a case X node, an exit is
"bypassed" for an approach when a one-way road leaves the approach road upstream (at the junction where the walk back
from the node stops: `Walk.follow` "in", 200 m / 6 segments) and, followed forward (`Walk.follow` "out", 400 m / 10
segments), ends at the junction where the exit road's walk out from the node stops (200 m / 6 segments). At most
`X.BYPASS_MAX_ROADS` (8) one-way roads are followed per node. Bypassed exits leave the approach's exit list before
the lanes are allocated, except the straight exit, the last exit of an approach, or an exit road no other approach
still feeds. `X.defaultConns` (Reset model) keeps every exit. Log: `kind=slip ... case=X ... bypass=<count>`. The
slip lanes' own diverge / merge nodes are case B as before.

Also from the player's hand edit at that node (approach of 3 lanes, right turn served by a slip lane: curb straight,
middle straight, far lane straight + left): with a straight exit the far turn lane always goes straight too
(`X.allocate`: [straight, far] x 3 lanes `1-1 1-1 1-2`; [curb, straight, far] x 4 lanes `1-1 2-2 2-2 2-3`); the curb
lane stays turn-only when a curb turn exists.

Unit tests (test_cross.lua): F.channelX (four corner slip lanes) 1-3 x 1-3 lanes both sides, F.channelT centre,
mirrored connections, default model unchanged, a one-way road ending elsewhere, a slip chain at / past the cap, a
one-way loop, the per-node budget.

Review 2026-10-11 (guards against false positives): the one-way road must leave U and reach J within
`X.BYPASS_MAX_DEG` (100) of the traffic's heading there (Channelized Junction slip lanes: 40-80 deg; a roundabout
splitter's entry leg or a dual carriageway's other half next to a crossroads is a U-turn at U and was taken as a
bypass before), and be a shortcut: shorter than `X.BYPASS_SHORTCUT` (0.9) times U -> node -> J (slip lanes: chord /
(Lm + Ls) <= 0.75; a one-way street round a town block of a crossroads is exactly as long and was taken as a bypass
before, so the curb turn at the crossroads was removed). No sidewalk test: the Channelized Junction's slip lanes are
town one-way xsmall with sidewalks. Tests: splitter leg (U-turn), one-way block ring, a diamond interchange's
terminals (the highway is no bypass), slip angles 40-80 deg with unequal set-backs, printed cost (Channelized X
centre about 0.15 ms; worst case 4 x 6 + 8 x 10 + 4 x 6 segment steps per node, each one-way road followed once).
Not detected (the full crossing rule, as before): the Channelized Junction with splitter islands (the centre is two
nodes and the slip lanes end beyond the split nodes, so the exit road's first junction is the split node, not the
slip lane's end) and long jughandle loops.

Checks:
1. Place a Channelized X (near-side slips, no splitter islands). Centre APPLY line: `case=X ... bypass=4`. Open
   the centre in the Smart Lanes tool: no approach has a right turn (left in left-hand traffic); every lane of every
   approach goes straight, the far lane also turns the other way. Right turners take the slip lanes and nobody
   queues at the light to turn right.
2. Channelized T: the centre logs `bypass=2` (east approach straight only, side road turns away from the slip).
3. Reset at the centre: the game's full default comes back, right turns included.
4. A plain crossroads (no slip lanes): no `bypass=` field; lanes as in section K, except the far lane of a 3+ lane
   road now goes straight too.
5. Open: the Channelized X with splitter islands (the centre is not a two-way crossroads there) and jughandles were
   not tested in game.

## S. Tool: Shift+click multi selection, lane view of every selected junction (rev 4, PHASE7.md step 5b)
With something selected, Shift+click (the "(Hold)" modifier read at the click, as in section O) adds to the
selection, which becomes a "multi" selection (head "%d junctions selected", detail "Apply to junction or Reset:
every selected junction"): a handled junction is added, or removed when it is selected already (the last one
removed: nothing selected); a road adds its Shift street (section O follow mode, 10 junctions / 1 km); a roundabout
(between its junctions) adds its junctions. A street or roundabout that holds the whole selection replaces it
instead (a plain-clicked street Shift+clicked again is followed further, as in O; ring junctions + their ring = the
ring). Shift+click with nothing selected, or with an unhandled junction selected, is a plain pick. A plain click
starts a new selection; right click / Esc clears. Cap `Core.MULTI_MAX` = 60 junctions: past it the rest is dropped,
`SKIP src=tool scope=multi reason=cap max=60 dropped=..`, status "Selection full: at most 60 junctions". A plain
node, a dead end, a 5-arm junction: "Not handled: not added to the selection", the selection unchanged
(`PICK target=multi op=none item=..`).
Rings (decision 2026-10-11): ring arm junctions join the multi selection. Apply plans them in the batch job with
`Rules.planRing` seeded with that batch's selected junctions of each ring (exactly what Apply to junction writes
there, turbo decision ring-wide as before), Reset writes the engine-default model (`RESET mode=model scope=multi
ring=..`). Apply to roundabout (one Apply since rev 6) stays off for a multi selection. Plain / "left alone" ring nodes are not added.
Lane view: the game's NodeViewer takes a map node -> lane list (`builtin.d.tl` NodeViewerParam), which the tool has
used for whole rings since Phase 2, so ONE NodeViewer carries every selected junction (at most `Core.VIEW_MAX` = 60),
streets included now. Each node's entry is built from its own connections and network read together; a node whose
network has fewer edges than connections, or that is gone, is left out (crash rule 9); nothing while a write is
pending. For streets / multi selections the spec is kept while the selection's signature (re-read every 30 frames)
is unchanged, at most 30 frames, so a hover re-render does not read 60 nodes. Markers: a circle at every selected
junction (positions from the 30-frame re-read), no segment highlight.
Log: `PICK target=multi op=add|remove|none item=node:<id>|street+:<seg>|ring:<key> added=.. removed=.. junctions=..
nodes=<ids> badge=..`; Apply / Reset `MULTI op=apply|reset junctions=.. batches=..`, then per node `APPLY src=tool
scope=multi kind=slip|drop node=..` or (ring junctions) `APPLY src=tool scope=multi layout=turbo ring=.. node=..
lanes=.. dir=.. exits=.. entries=.. turbo=.. turbo_reason=.. before=.. after=..`, `RESET mode=.. scope=multi ..`,
`SKIP src=tool scope=multi [ring=..] node=.. reason=gone|no_config|conns|plain|<classify reason>`, per batch (40 nodes,
one proposal, one per frame) `WRITE src=tool|reset scope=multi batch=i/n nodes=.. success=..`, `VERIFY ... scope=multi
same=.. nodes=..`. Re-read: `SKIP src=tool scope=multi nodes=<ids> reason=gone` for bulldozed junctions.
1. Select a crossroads, Shift+click two more crossroads and a lane drop: "4 junctions selected", a marker and the
   lane arrows on each of the 4 at once. Shift+click one again: removed (3), its arrows gone. Note whether the
   NodeViewer really draws several distant junctions (it did for a ring's junctions).
2. Shift+click a street between junctions: its followed junctions join (up to 10). Plain-click a street, Shift+click
   the same segment: "Street: N junctions" further along (not a multi selection).
3. Shift+click two junctions of a roundabout and one slip-lane junction; Apply to junction: the two ring junctions get
   what Apply to junction gives each (exit-only outer lane where the ring allows), the other ring junctions untouched,
   the slip junction its slip rule; one WRITE line, every VERIFY `same` = `nodes`. Apply to roundabout off (one Apply since rev 6). Reset:
   ring junctions back to the game default, the slip junction to its lanes before Apply. Lights: ring and slip
   junctions as with Apply to junction there (setting "No lights at roundabouts and ramps").
4. Lane status: mixed selection "Smart lanes on k of N junctions"; all applied "Smart lanes"; crossroads and ring
   junctions only, untouched: "Game default"; with a slip / drop junction in it: "Game or custom lanes" (rev 5; "Custom" before).
5. Cap: Shift+click streets until 60: the status says "Selection full: at most 60 junctions", the SKIP line logs
   the dropped count; Apply writes 2 batches (40 + 20) on consecutive frames, no hitch.
6. Crash checks: select several junctions, bulldoze one BEFORE Apply: within half a second it leaves the selection
   (`SKIP ... reason=gone`), its arrows vanish, no crash; Apply writes the rest. Bulldoze one right after pressing
   Apply: `SKIP ... reason=gone` in the batch. Rebuild a road of a selected junction (new segment ids): its arrows
   come back from the new connections after the re-read.
7. Hover with a selection: the cursor tooltip ends "Shift+click: add a junction or road", over a selected junction
   "Shift+click: remove from the selection". SQPERF `world_render` / `select` stay low with 60 junctions selected
   while sweeping the cursor (the NodeViewer spec is not rebuilt per hover change).
8. In game 2026-10-11 (in-progress 5b files, Channelized X centre + 4 slip nodes): Apply / WRITE / VERIFY and the
   combined lane view worked, but `ERROR where=highlight ... sl_write.lua:96: table index is nil` was logged 68
   times: the highlight asked for the multi target's (missing) `t.node` segments. Fixed (`segsOf` returns none for
   a multi target; `world.node` / `world.seg` return nil for a non-number id) and tool ERROR lines are capped now
   (`Pick.errorGate`: 3 per `where=`, 20 per session, the last one ends `more=suppressed`). Check: no ERROR line
   with a multi selection while hovering and after bulldozing a selected junction.
9. In game 2026-10-11 ~19:11: after a multi Apply (8 junctions, 6 written, VERIFY in the same second) the lane view
   stayed hidden 20+ s. Cause: the world layer renders only when the core's version moves; the render while the
   write was pending got an empty spec, and the re-read after the VERIFY found the same signature as the refresh
   right after the callback, so nothing re-rendered. Fixed: `C.nvHeld` remembers an empty spec handed out while
   held, and `C.step` re-renders (fresh spec, cache dropped) on the frame the write is judged; the street / multi
   spec cache also never outlives a refresh. Check: after Apply (multi, street, single junction) the arrows are
   back within about half a second, showing the new connections.
10. Review 5b: the toolbar's lane status chip shows only the state ("Smart lanes", "Game default", "Custom lanes",
   "Smart lanes on 4 of 6 junctions"; nothing selected: "Click a junction or a roundabout"); the "Current lanes: "
   prefix is gone (user 2026-10-11), and its tooltip starts with "Smart lanes: what Apply sets." A multi batch
   junction whose ring check fails is skipped (`ERROR where=multi_ring`), never planned as a street node.

## T. Shallow ramps on a two-way road: nothing across the oncoming carriageway (rev 4, sl_cross X.shallowRamps)

In game 2026-10-11 (user screenshots 19:12, log 02:11Z): an interchange whose one-way ramps leave and join a two-way
3+3 road. Nodes 60950 and 64312 (a 2-lane ramp out on each side: `64312 roads=60343@-35(0,2);64315@125(0,2);
65415@45(3,3);93466@-135(3,3)`) were applied as crossroads, `lanes=65415:k|s|sf;..`: the far lane went straight
and turned across the oncoming lanes into the ramp on the far side. Cause: at the node the ramps' tangents were
80-100 deg off the road (both nearest one travel direction, or 90+), so sl_slip's case B ("two_branches_one_direction"
/ "branch_turn" / "far_side_branch") handed the node to the crossing rule. Node 60274 (4-lane ramp out at -40,
4-lane ramp in at 130 on a 45 / -135 road, tangents 85 deg off) was case B by a margin of 5 deg.

Rule (user decision 2026-10-11: shallow ramps only; terminals keep their left turns):
- Shallow: a ramp (one-way, no sidewalk) whose chord over its first 50 m (`X.SHALLOW_LOOK`, Walk through plain
  nodes, the point on the Hermite curve) is at most `X.SHALLOW_MAX_DEG` = 60 deg off the line of the node's two-way
  through road (two two-way roads within 45 deg of straight both ways). It belongs to the travel direction on whose
  curb side it lies. Evidence for 60: square_roundabouts' only ramps meeting a two-way road are the Highway
  Interchange's terminals, which meet the cross road square: parclo stubs and wrapped diagonals end in a straight
  edge of 49+ m (90 deg), diamond climb edges are one Hermite edge with both tangents along the highway: chord over
  50 m 85 / 78 / 80 deg (S / M / L; whole edge 86 / 74 / 68). Its own shallow ramps leave one-way carriageways
  (case A). Ramps peeling off alongside a road: about 25 deg (the test fixtures). The log line names every ramp's
  angle: `ramp_deg=<seg>:<deg>,...`.
- sl_slip case B first: when the tangents do not decide, every branch a shallow ramp heading along its curb-side
  direction, one per direction -> the slip-lane rule (`split=shallow tangent=<why the tangents failed>`): diverge with
  the exit-only curb lane (section N), merge with the look-ahead (section L). These nodes lose their traffic lights
  like every slip node (setting "No lights at roundabouts and ramps").
- Terminals (follow-up 2026-10-11): when the tangents DO assign every branch (a ramp end leaning under 90 deg towards
  one direction at the node), a ramp among them whose 50 m chord is more than 60 deg off the road is a ramp end
  meeting it at about a right angle (diamond / parclo terminal), not a slip lane: the node goes to sl_cross
  (`slipReason = "terminal"`, the APPLY line shows `case=X ... ramp_deg=<seg>:<d>` with d > 60) and the ramp keeps
  its turns both ways. Town one-way streets (sidewalks) and ramps whose chord is 60 deg or less stay slip nodes.
- Otherwise sl_cross (a two-way side road at the node, a far-side or backward ramp, a mix with a steep ramp):
  through-road approaches reach a shallow ramp out only from its curb-side direction; a shallow ramp in only joins
  that direction's carriageway (into its curb lanes) or a side road on its own side. Logged `shallow=<approach>>
  <exit>,...`. Reachability first (follow-up 2026-10-11, as the slip-lane bypass guard): a blocked move stays when
  it is the only feed of its exit road, so a shallow ramp on the far side (a left exit from a two-way road in
  right-hand traffic) keeps the far turn of the approach it leaves (from the far lane, which also goes straight); a
  joining ramp whose every move is blocked keeps them (defensive: its own carriageway is always a way on). Logged
  `shallow_kept=<approach>><exit>,...`. A far-side joining ramp only goes onto the near carriageway, however sharp.
  Two-way side roads keep the crossing rule; ramp -> ramp stays excluded.
- Three two-way roads and a one-way road (a side road at a ramp node) are now crossings (case X), not "none".

Unit tests: test_slip.lua "shallow ramps ..." (60274 layout with tangents 85 / 95, 60950 / 64312 layout with
tangents 80 / 90 / 100, the 60 deg threshold both ways), test_slip.lua "ramp terminals ..." (ramp out and in with
tangent 80 / 85 / 89 and chord 80-90: crossing rule, both turns; the same ramp curving to a 30 deg chord and town
one-way streets: slip nodes), test_cross.lua "shallow ramp ..." (side road with a ramp out and a ramp in, far-side
ramp out kept reachable / ramp in, the joining-ramp guard with a stubbed X.shallowRamps, diamond S / M / L
terminals keep both turns); both traffic sides.

Checks:
1. Select nodes 60950, 64312 and 60274 (Shift+click) and Apply to junction. APPLY lines: `case=B ... split=shallow
   tangent=two_branches_one_direction ramp_deg=60343:<d>,64315:<d>` for 60950 / 64312 (each ramp angle well under
   60), 60274 `case=B shape=diverge+merge` (split=node or shallow). If a ramp logs more than 60 the node stays a
   crossroads: note the angle (the threshold or the 50 m chord may need tuning).
2. Lane view, compare with the user's second screenshot: through lanes straight, only the curb lane of each
   direction into the ramp on its own side (exit-only), no arrow from a far lane across the oncoming lanes into a
   ramp; at 60274 the joining ramp only merges into its own carriageway, no left turn across the road.
3. The ramp ends at the other road (64761, 64876, 67667, 68527: ramps meeting it at about a right angle) still turn
   both ways (`lanes=..:k|f`), no `shallow=` field.
4. Traffic: ramp traffic leaves and joins without stopping oncoming traffic; nobody queues in a far lane to cross.
5. (review) A hand-built tight loop ramp meeting a two-way road square (parclo A2 off-loop): the chord over 50 m of a
   loop of radius R that arrives perpendicular is 90 - deg(25/R) off the road: R 30 -> 41, R 40 -> 54, R 50 -> 61,
   R 60 -> 66 (unit probe). Below about R 48 the loop counts as shallow and its left turn at the terminal is left out
   (`shallow=<loop>><road>`). Check whether players' loops get that tight; if so lower `X.SHALLOW_MAX_DEG` towards
   the logged `ramp_deg` of the interchange ramps (check 1) plus a margin.
6. A far-side shallow ramp out (a left exit from a two-way road in right-hand traffic, no side road at the node):
   APPLY line `shallow_kept=<approach>><ramp>`, no `shallow=` for it; the lane view shows the approach's far lane
   going straight and into the ramp; vehicles routed onto the ramp take it (they cross the oncoming lanes, as at
   any left turn).
7. A ramp end meeting a two-way road at about a right angle whose tangent at the node leans under 90 deg (a
   hand-built diamond terminal with a short curved stub): `case=X` with `ramp_deg` over 60, turns both ways
   (`lanes=..:k|f` / `ks|sf`), not `case=B shape=diverge`.

## U. Performance: SQPERF sections to read (rev 4, PHASE7.md step 7, PERF_REVIEW.md "Phase 7")

Set **Debug: performance log** On (or enable the DEV mod `square_sqperf_all`), play, then `make perf` (or
`grep SQPERF stdout.txt`). Lines `mod=square_smart_lanes ctx=gui`: every 30 s one summary per instrument
(`name n= ms= max=`); a call over 16 ms logs `slow=<section> max=..` even with the setting Off.

Automatic pass, per frame (game script's GUI instrument, `ctx=gui`): `gui_update` with `job_step` (one frame's
share of the job in progress: a job runs in steps over frames within an 8 ms budget, PERF_REVIEW.md 2026-10-12)
and `verify` (one frame's share of verifies and re-checks); counters `job_nodes` and `job_frames` (frames per
job = `job_frames` c / `job` n). Per job (`ctx=gui_job`, the summed work of its frames, never `slow=` lines):
`job` with `job_ring` (ring search at every node, ring plans and proposals), `job_classify` (the slip /
crossing / drop plans with their walks), `job_write` (each node's entry and the proposals; also counted in
`job_ring` for rings), `job_audit`.
Tool (its GUI instrument): `hover` (Selector, per frame) with `resolve` nested (a new hover target), `select`
with `resolve` / `multi_add` (a Shift+click into the selection), `step` with `refresh` (the selection's re-read
every 30 frames) and `batch` (one street / multi batch: plans + proposal), `world_render` with `highlight` and
`nv_spec` (the lane view's spec, only when built), `badge` (badge + button states of a target; nested in
`resolve` / `refresh`), `apply_node` / `apply_ring` / `reset`.

Checks (compare with the offline numbers in PERF_REVIEW.md; in game reads cost more):
1. Build something big at once (paste a town grid, a long avenue over many crossroads, a Channelized Junction
   interchange, the Stress Test Lights showcase at 8x): one `job` (ctx gui_job) per build; note `max` of `job`,
   `job_write`, `job_classify`, `job_ring`, `job_nodes` and `job_frames`. `job_step` and `gui_update` should
   stay at about 8-10 ms max (no `slow=job_step` / `slow=gui_update` lines); a slow line names a frame hitch:
   note the build. The SQRL lines are those of before (one SUMMARY / WRITE kind=slip / VERIFY per job), the
   lane writes come as several proposals (one per frame that built entries).
2. Tool: Shift+click 40-60 junctions one by one: `multi_add` / `select` max stays low (offline 0.6-1.5 ms per
   click at 60), also for the last clicks.
3. Keep 60 junctions selected for 30 s: `refresh` n is about 60 per 30 s, max small (offline 0.3 ms).
4. Select a long street (plain click on a 2-3 km road between two crossroads, and a Shift street of 10
   junctions on a one-way street): `refresh` max (offline 1.0 / 1.3 ms; the long street re-walks every 30 frames).
5. Sweep the cursor slowly along a 3+ km road (longer than the 3 km street cap) and along a long one-way street:
   `hover` max and `resolve` n (offline 0.1 ms per frame on average).
6. After an Apply or Reset the badge and the lane view update within a second (the caches follow the new
   connections; a write drops the hover world).
7. APPLY lines of ramp ends and one-way streets meeting two-way roads show `case=X via=<reason>` (terminal,
   far_side_branch, branch_turn, main_bend, two_branches_one_direction, three_two_way, one_way_square).

## V. Roundabout on-ramps: the ramp keeps its own ring lane (rev 4, sl_rules M.rampEntryConns / M.rampEntryWhy)

In game 2026-10-11 (square_roundabouts Roundabout Interchange, 2-lane ccw ring 63759, right-hand traffic): the user
hand-edited node 63772, an entry-only junction (ring in 63640, 1-lane on-ramp 63644, ring out 63650, no exit), to
`63640:1>63650:1, 63640:2>63650:1, 63644:1>63650:2`: the ramp takes the outer ring-out lane alone and both
circulating lanes zip into the inner one (the ramp never yields). Our Apply (`turbo=false turbo_reason=narrow_exit`)
wrote `63640:1>63650:2, 63640:2>63650:1, 63644:1>63650:2` (the ramp merging into the outer lane, give-way).

Rule (variants two_lane = the automatic pass and turbo = the tool's Apply; Reset / engine model and "matched"
unchanged): at a ring junction with entry lanes and no exit lanes, entry lane j -> ring-out lane j (curb first),
ring lane i -> ring-out lane max(i, N + 1) (outer first; the R circulating lanes fold into the inner R - N lanes,
aligned from the inside, the outer ones zip into lane N + 1; no crossing). Only when all hold, else today's
give-way entry with the first reason:
- `one_lane_ring`: R >= 2;
- `wide_entry`: N < R entry lanes;
- `not_ramp`: the arm is a ramp: one-way without a sidewalk (sl_cross X.isRamp; town arms and splitter legs keep
  give-way);
- `narrow_next_exit`: the next ring junction downstream has an exit of at least 2 lanes (so traffic in either ring
  lane can leave right after the zip and the merge does not queue on the ring; orchestrator / user 2026-10-11);
- `reachability`: with the new connections (planned ones at seed junctions, current ones elsewhere, the engine model
  where a node has none) every entry on the ring still reaches every exit and no ring lane is dead
  (`Rules.reachability` with lane changes between nodes, as the matched rule relies on). With lane changes the fold
  itself cannot break this; it guards against broken connections elsewhere on the ring.
APPLY lines of entry-only junctions get `entry=own_lane` or `entry=give_way why=<reason>`.

Node 63771 (next junction, 3-lane arm 127589): our output (log 03:07:55) is exactly the user's description: outer ring
lane 63650:1 -> 63649:2 + curb exit lane 127589:6; inner 63650:2 -> 63649:1 + 127589:5, :4; entries 127589:1 ->
63649:2, :2 and :3 -> 63649:1 (`after=8`). Nothing to change there.

Unit tests: test_rules.lua "ramp entry ..." (fixture F.interchange: the 63772 + 63771 layout, both ring directions and
traffic sides, two_lane and turbo; the exact indices of the user's edit; town arm, 1-lane ring, 2-lane ramp, 1-lane
or entry-only next junction, a broken downstream junction -> unchanged; 4-lane ring), test_script.lua (automatic pass
`entry=own_lane`), test_tool.lua (the user's edit reads Smart lanes, Apply writes it, Reset the engine model).

Checks:
1. Select ring 63759's junctions 63772 and 63771 (Shift+click) with the user's edit in place: the badge reads
   Smart lanes for 63772 (and the ring or selection reads Smart lanes where the rest is ours).
2. Reset both, then Apply to junction: APPLY `node=63772 ... entry=own_lane after=3` and `node=63771 ... after=8`
   (no entry field). Lane view at 63772 equals the user's version: ramp into the outer lane alone, both ring lanes
   into the inner lane.
3. Apply to roundabout on ring 63759: every entry-only ramp junction of the Interchange logs `entry=own_lane` or
   `entry=give_way why=<reason>`; note any `why=narrow_next_exit` / `reachability` and whether that is right there.
4. Traffic: ramp traffic joins without stopping; the zipped inner lane does not back up through the previous
   junction (if it does at busy times: note it, the next-exit condition may need to be stricter).
5. A town roundabout with a one-way town street (sidewalks) joining at an entry-only junction keeps
   `entry=give_way why=not_ramp`.
6. A fresh Roundabout Interchange (automatic pass): APPLY lines as in check 3 without using the tool.

## W. Crossroads and T-junctions: no lanes squeezed inside the junction (rev 4, sl_cross X.allocateView)

User report 2026-10-11 (Roundabouts & Interchanges interchange, smart lanes applied): "these turns are inefficient
... e.g. 4 lanes turning into 1". Log 03:16:26: T-junctions 128660 `lanes=128641:k|k|k;128645:k|f|f|f` and 128948
`lanes=128643:k|f|f|f;128652:k|k|k` (`before=19 after=9`): a 3+3 two-way stem, a 4-lane one-way road in and a
4-lane one-way road out (19 = 4 x 4 + 3 in the game's model). The stem's 3 lanes turned into the out road's lanes
1-3 and the one-way's 3 far lanes into its lanes 2-4: lanes 2 and 3 fed twice, while the stem (3 lanes) got 1.

Rule now (sl_cross header, X.allocate caps, X.allocateView, placeExit):
- per approach, an exit's lane block is at most that exit road's lane count; the lanes left over go to exits with
  room: straight, then the far turn, then the curb turn (contiguous, no crossings; curb lane turns only on 3+ lanes,
  2 lanes share, 1 lane everything). A shared lane (2 lanes; the far lane also going straight) only where the
  straight exit has a lane for it;
- across approaches: while an exit road gets more feeding lanes than it has, the widest turn block into it gives a
  lane back to its approach's other exits with room (towards 1 lane each). Straight blocks and the shared lanes stay;
- only an approach with more lanes than all its exits together folds (where it adds the fewest lanes per exit
  lane; the widest exit first), logged `squeeze=<approach>:<lanes folded>`;
- in each exit road: curb turns its curb lanes, far turns its far lanes, straight next to the far turns; with too
  few lanes, straight shares with the far turns first, and all feeders are spread evenly when that would pile more
  onto one lane than ceil(feeders / lanes).
Expected at the two nodes: 128660 `lanes=128641:k|k|k;128645:k|k|k|f`, 128948 `lanes=128643:k|k|k|f;128652:k|k|k`
(stem into the out road's lanes 1-3, the one-way's far lane into lane 4, its 3 curb lanes 1:1 into the stem).
Shared exit lanes remain where a road is too narrow for every movement into it (2x2 crossroads, 1-lane roads) and
where the far lane's straight share meets the far turn from the left (3x3 crossroads, as in the user's Channelized X
hand edit); crossroads keep the game's lights there. The game-default model (Reset) is unchanged.

Unit tests: test_cross.lua "no squeeze: ..." (4-lane approach, 1-lane turn or straight exit; the two user T layouts
with the log's lane strings as "before"; unavoidable folds with `squeeze=`; exhaustive T / X / one-way shapes, 1-5
lanes in, 1-4 out, both traffic sides: no crossing, every lane connected and fed, the most feeders per exit lane
never above ceil(feeders / lanes), a turn block wider than 1 into a full road only where its approach has no room).

Checks:
1. Select 128660 and 128948 (Shift+click), Apply to junction: APPLY lines show the expected `lanes=` above, no
   `squeeze=`. Lane view: the stem's 3 lanes into the out road's lanes 1-3, the one-way road's lane 4 alone into
   lane 4, its lanes 1-3 one to one into the stem. Compare `after=` with the old 9.
2. Traffic at both nodes: no queue where lanes merged inside the junction before; note whether 3 lanes back into
   the stem is more than the traffic needs (the one-way road's lanes 2-3 used to go to the out road).
3. The other nodes of that selection (128944, 128949, 128946, 128659): lanes= unchanged or only turn blocks smaller;
   note any `squeeze=`.
4. A town 3x3 crossroads and a 2x2 one: lanes as before (k|s|sf, ks|sf).
5. A road ending at a narrower road (e.g. a 4-lane one-way street into a 1+1 street): `squeeze=<seg>:2`, two lanes
   each way, never 3 + 1.

Review 2026-10-11: the reduction loop ends (a turn block's cap only shrinks, a reduction never pushes another exit
road over its lanes, failed tries reset only after a success); over 1920 T / X / one-way shapes it needs at most 3
re-allocations per node (MAX_REDUCE 100 is a safety cap only; the result with 8 equals the result with 100, and a
loop cut after 1 step keeps every invariant). Deterministic (no `pairs` in the path; the exit sort keys are unique):
same connections run to run. An approach that already folds is no candidate and a re-allocation that would fold is
recognised from the caps' total without calling X.allocate (same results; the 5+1 crossroads went from 0.05 to
0.014 ms). Cost: allocateView 0.01-0.04 ms per node offline (0.005-0.007 ms for the old uncapped loop; the whole
plan 0.1-0.2 ms); the 160-node jobs unchanged within noise (mixed 14-16 ms, Channelized X centres 51-54 ms).
Tests: test_cross.lua "squeeze review: ..." (allocate with caps over every exit list and cap vector; allocateView
bounds / determinism / cost; Channelized X and T centres of 1-4 / 1-3 lanes: bypasses then caps). Ring review
follow-up: X.isRamp calls Rules.isRampSeg (one implementation).

## X. Junction audit: find inefficient lane setups from the log (rev 4, sl_audit.lua, `make audit`)

User request 2026-10-11: find inefficient lane setups automatically instead of checking every junction by eye.
`sl_audit.lua` (pure, bounded, nil-safe) looks at one junction's road connections and counts findings; the
automatic pass, the tool's Apply and the tool's picks log them; `tools/sqrl_audit.py` (`make audit`) sums them up.

Findings (only AVOIDABLE ones count; forced squeeze / sharing go to `forced=`, never a reason for a line):
- `squeeze`: an exit lane fed by k > 1 lanes of one approach (+k-1). Forced up to the exit road's pressure
  (sum over the movements into it of what each approach must put there when its other exits take all they can,
  less the road's lanes): a lane drop 3 -> 2, a ring entry wider than the ring, a ramp's own-lane merge, a ring's
  ramp entry. Four lanes into one where the approach had room elsewhere is avoidable.
- `shared`: an exit lane fed by m > 1 approaches (+m-1), avoidable only when the movements' needs fit the exit
  road's lanes (an allocation without sharing exists there; a per-exit approximation that ignores the approaches'
  other exits competing for the same lanes). A 2x2 crossroads (3 movements, 2 lanes), give-way merges and a
  ring's entry give-way are forced. Also forced: as many shares at an approach's exits as its excess (its lanes
  over what its exits have left once every other movement into them has a lane, at least 1 per exit; a 2x3 T's
  3-lane side road: 1). Detail `shared:<exit seg>:<kinds>`: the first shared lane's movements at a
  crossroads, k curb turn / s straight / f far turn.
- `shared_lit` (section Y; under `forced=`, by design, never a reason for a line): at a crossroads with traffic
  lights, an exit lane a straight movement shares with a turn from another approach.
- `across`: a move across the opposing carriageway into or out of a shallow ramp (sl_cross X.shallowRamps),
  unless it is the exit road's only feed or the approach's only way on (or the crossing rule kept it:
  `shallow_kept`).
- `ramp_ramp`: a ramp straight back onto a ramp at a node with a two-way road, while a road is there. A ring's
  own segments are never ramps (section Z).
- `u_turn`: back onto its own segment, or a turn over 135 deg, while the approach has another way on.
- `unfed` / `dead`: an outgoing road lane nobody feeds / an incoming road lane without a connection, although
  the rule's model (or, at an unhandled junction, the geometry) has a way there / on. `turbo_gap` (under
  `forced=`, by design, section Z): the ring-out outer lane after a turbo ring's exit-only junction.
- `bypassed_turn`: a turn allowed at a crossroads although a slip lane serves it (X.bypasses), not straight,
  while another feed of the exit road is kept that is no bypassed turn itself (section Z).
- `weave` (heuristic): an exit road at most 80 m long whose far end is a junction: per movement into it, the
  exits of that junction no lane it feeds reaches there (its traffic must change lanes within 80 m). Avoidable
  only as far as free lanes of the exit road next to the movement's would reach those exits; the rest is
  `forced=weave:n` (section Z). One segment only; ring segments and junctions without known connections are not looked at (automatic pass: only junctions
  planned in the same job, asked before the far junction's roads are read, so no extra reads).
- `lights`: a roundabout arm junction or a slip node (cases A / B) that still has a traffic light (tool picks
  only: the automatic pass removes them after its write anyway).
- `bad`: a road connection naming a segment or lane that is no road lane of the node now.
Candidate exits (what "an approach could go there" means) come from the rule's own model where the junction is
handled (crossroads: the approaches' exits after the shallow-ramp and bypass filters; slip nodes and lane drops:
their streams; ring junctions: ring on / exit / enter), else from the geometry as the crossing rule would pick.

Log lines (always on, no setting: quiet junctions log nothing; English):
- `[SQRL] AUDIT node=<id> case=X|A|B|D|ring|- shape=.. findings=kind:n,.. [forced=squeeze:n,shared:n] detail=<up
  to 6 short items> src=auto job=<seq>` per junction with findings, after the job's proposals were sent;
  `src=tool [scope=street street=..|scope=multi|ring=..]` after the tool's Apply (the connections it planned,
  written or already set); `src=pick` on a pick (current connections, lights read).
- `[SQRL] AUDIT_SUMMARY src=auto job=<seq> audited=<n> flagged=<n> findings=.. forced=.. [failed=<n>]
  [unlogged=<n>] skips=<SUMMARY's>` after each automatic job's SUMMARY. A job logs at most 40 AUDIT lines
  (`Audit.MAX_LINES`, review 2026-10-11: a 160-node build of 2x2 T-junctions would flag every one);
  `unlogged=` counts the flagged junctions over the cap, whose findings are in the totals only. Only the
  job's first audit failure logs an ERROR line (`failed=` counts them all). The tool's lines are bounded by
  its own caps (a pick: 60 junctions, an Apply batch: 40).
- `PICK ... findings=<sum>`: the picked junction(s) (a node; a ring's or street's junctions; for a Shift+click the
  junctions it added). Errors: `ERROR where=audit` (never thrown into the write path).

How to run (Stress Test, empty Blank Slate map, Smart Lanes "Apply automatically" On):
1. Stress Test > Towns tab > **Junction test** (Roundabouts & Interchanges enabled; e.g. All types, or each type
   in turn) and **Crossing test** (Size Medium, Lights Off). Wait for both summaries (`[SQST] ... done`).
2. Optionally pick junctions with the Smart Lanes tool (plain click, a street, Shift+click several): their
   current connections get audited (`src=pick`).
3. `make audit` (or `make audit ARGS='--last --src auto'`, `LOG=<copy of stdout.txt>`): findings by type, the
   worst junctions per finding (node, case, shape, detail), AUDIT_SUMMARY totals, skip reasons. Select a listed
   node with the tool to see its lanes (its PICK / AUDIT lines repeat the findings).
Expect (offline, test_audit.lua "standard fixtures"): no squeeze / across / ramp_ramp / u_turn / unfed / dead /
bypassed_turn / weave on Channelized T / X, ramp nodes, merge / diverge nodes and roundabouts. `shared` IS flagged
where the crossroads rule lets a straight movement keep an extra lane that a turn into the same exit road then
shares (detail `fs` / `ks`): the 2-lane "the lane next to the straight exit also goes straight" (T main road) and
the 3-lane "the far lane goes straight too" (the user's Channelized X hand edit) rules, e.g. a 3x3 crossroads
shared:4, a 2x2 T shared:2, the Channelized T / X centres 1 / 2, a 3+3 road where a 2-lane ramp joins beside two
straight lanes 1. These are the rule's trade-off of straight capacity against a shared exit lane, reported for a
decision, not hidden. Under traffic lights the two movements run in different phases, so the sharing costs
little there. (User decision 2026-10-11, section Y: the shares stay only at lit crossroads, audited there as
`shared_lit` under `forced=`; at unlit ones the rule drops them. The counts above are for an unknown light
state, as in the fixtures.)

Checks in game:
1. `make audit` after the two tests: note the top findings; for `weave`, `across`, `squeeze` select the listed
   nodes and judge whether the lanes are really inefficient (weave is a heuristic).
2. Pick an untouched game-default crossroads next to a Channelized X: `findings=bypassed_turn:..` (and squeeze /
   shared from the game's fan); Apply: the AUDIT src=tool line shows only the rule's shared lanes.
3. A slip node with a traffic light standing (setting "No lights at roundabouts and ramps" Off): pick it: `lights:1`.
4. No stutter on a big build (SQPERF `job_audit` section; offline 0.01-0.04 ms per junction).

Cost (offline, `uv run tests/run_tests.py -j 1 -k "audit's share" mods/square_smart_lanes`): the 160-node mixed
job 6.3 -> 8.1 ms (1.5 ms inside the audit), 160 Channelized X centres 6.4 ms inside the audit on a 43-48 ms job
(within the job's noise); component reads unchanged (BN / BE / BNC equal with the audit stubbed). A pick of a
10-junction Shift street plus a Shift+click: 1.43 -> 1.62 ms for 3 picks, +1 config read per pick (the weave
look-ahead and the lights state).
Tests: test_audit.lua (each finding both traffic sides, standard fixtures, nil-safety, caps, log fields, cost),
test_script.lua / test_tool.lua "audit: ..." (lines, sources, a failing audit never loses a pick or a write),
tests/tools/test_sqrl_audit.py (the report; `make test-tools`).

## Y. Crossroads: the extra straight lane only under traffic lights (rev 4, sl_cross X.allocateView, X.litOf)

User decision 2026-10-11 ("Keep where lights exist"): the crossroads rule's extra straight shares (2 lanes: the
lane next to the straight exit also goes straight; 3+ lanes: the far turn lane also goes straight, the user's
Channelized X hand edit s|s|sf) make the straight movement share an exit lane with a turn from another approach
(section X `shared`). They now stay only where the node has traffic lights (the two movements run in different
phases). At an unlit node, an approach's extra share whose straight exit road gets more feeders than it has
lanes is dropped (before any turn block gives a lane back), so the two movements never meet in one exit lane:
3x3 crossroads `k|s|f` instead of `k|s|sf`, 2x2 T main road `s|f` / `k|s` instead of `s|sf` / `ks|s`, Channelized X
centre `s|s|f`. Unchanged: 3+ lanes the curb lane turns only, 1 lane everything, 2 lanes and 3 exits still share
between their own movements (`ks|sf`), the game-default model (Reset).

"Lit" (sl_lights `L.litOf`, read by sl_write `world.lit(n)` = `W.lightState`, one config + one light-component read
per handled case X node per world, memoised; only case X nodes past the skip checks read it):
- preference YES, or AUTO with a `BASE_NODE_TRAFFIC_LIGHT` component: lit (`lit=yes`);
- preference NO: unlit (`lit=no`);
- AUTO without a light component, no config, no enum, a failing read: unknown (`lit=unknown`), planned as lit (the
  rule as before). Why: the game adds AUTO lights only from 1950 (`traffic_light_config.res.lua`
  trafficLightYearFrom) and only at some junctions, and whether every light already stands when the automatic
  pass reads the node is not proven. In game 2026-10-11 (Junction test log, LIGHTS src=auto ... `light=true` at the
  new Channelized X slip nodes, 43 of 315 AUTO nodes) the component can exist then; other new AUTO nodes (roundabout
  junctions on smaller roads) had none, and whether the game would have lit them later is not known.
So in practice unlit = lights switched off at the junction (node window, Stress Test Crossing test Lights Off).
Fixtures have no `world.lit`: unknown.

Log: `APPLY kind=slip ... case=X ... lit=yes|no|unknown [unshared=<approach segs>]` (unshared: the approaches whose
share was dropped). Audit: at a lit crossroads avoidable `shared` lanes a straight movement takes part in go to
`forced=shared_lit:n` (never flags a junction; turn + turn sharing stays `shared`); unknown nodes are audited as
before (`shared` avoidable); unlit nodes have no extra shares left. `make audit` lists `shared_lit` in the totals as
"by design" (tools/sqrl_audit.py BY_DESIGN).

Not automatic: switching a junction's lights on or off later (node window, Stress Test Lights option) does not
rewrite its lanes. The tool plans with the current light state, so its badge shows the junction as Custom within
`Core.NODE_STATUS_FRAMES` (300 frames: the per-junction status is keyed by segments + connections) and Apply to
junction writes the lanes for its lights. "No lights at roundabouts and ramps" never removes crossroads lights (keepsLights):
unchanged.

Unit tests: test_cross.lua "lights: ..." (allocate's third result and noShare over 1-6 lanes; 1-3 lane T and X both
sides lit / unlit / unknown with the unlit lanes and `unshared=` pinned, lit = unknown, Reset model unchanged;
Channelized X 1-3 x 1-3 and T centres: lit `s|s|sf`, unlit no shared exit lane on 2+ lane roads; one read per node,
memoised, a failing read is unknown, slip nodes never read; 576 unlit T / X shapes: invariants, squeezeCheck, no
share into a full exit road, shared lanes never grow), test_audit.lua "lights: ..." (lit: shared_lit only, unlit:
avoidable shared gone except the side road's 2-lane far turn at 3x3 T, which is no extra share and avoidable only
by taking a straight lane from the main road; at 2x3 T the same share is forced: the side road's 3 lanes have only
2 share-free exit lanes, the audit's per-approach excess; turn + turn still `shared`), test_lights.lua litOf, test_script.lua / test_tool.lua "lights: ..." (fake light enum and component:
one light read, `lit=` and `unshared=` on APPLY, AUDIT / AUDIT_SUMMARY, badge Custom after a light switch until
re-Apply), tests/tools/test_sqrl_audit.py SharedLitTest. Cost: +1 config read per case X node (160 Channelized X
centres: BNC 641 -> 801; time within noise).

Checks in game:
1. Stress Test Crossing test with Lights Off: every APPLY case=X line `lit=no`, 3x3 crossings `lanes=...k|s|f...` and
   `unshared=` on them; `make audit`: no `shared` on those crossings.
2. Crossing test with Lights On (year 1950+): note what `lit=` the fresh crossings log (yes = the component stands at
   the automatic pass, unknown = it comes later). Lanes as before (`k|s|sf`); `make audit`: `shared_lit` under
   forced, no `shared` from the rule.
3. Channelized X (Roundabouts & Interchanges, AUTO lights, 1950+): centre `lit=yes` expected (its slip nodes had
   `light=true` at the automatic pass), lanes `s|s|sf`. Switch the centre's lights off in the node window, pick it
   with the tool: badge Custom after a few seconds; Apply to junction: `lit=no unshared=...`, lanes `s|s|f`, no
   two movements in one exit lane in the lane view.
4. Before 1950 (AUTO, no lights): crossings log `lit=unknown` and keep the shares (open question: treat AUTO before
   1950 as unlit?).

## Z. Audit after the Showcase run: ring ramps, turbo gap, bypassed side roads, forced weave (rev 4, sl_audit.lua)

Stress Test Showcase 2026-10-12 (seed 747943: every roundabout and interchange type of Roundabouts & Interchanges
with random params, the automatic pass on every placement, 54 town street grids; log copy
`showcase_747943_stdout.txt`), src=auto, 2687 junctions audited. Each finding checked against the APPLY / SUMMARY
lines of the same nodes; all four were the audit misjudging the rule's output, so only `sl_audit.lua` and
`tools/sqrl_audit.py` changed (no lane rule changed, no Changelog line):
- `ramp_ramp` 86 (65 junctions, all `case=ring shape=arm`, detail `ramp_ramp:<ringIn>><ringOut>`): the circulating
  move. Interchange rings and the Magic Roundabout's mini rings (15 per Magic Roundabout: jobs 77 / 83 / 107) are
  one-way roads without sidewalks, which `Rules.isRampSeg` reads as ramps, and the arm is two-way. A ring arm
  junction has three roads (ring in, ring out, arm), so no ramp-to-ramp move is possible there. Fix: the audit
  never counts the ring's own segments (`opts.ring.segSet`) as ramps.
- `unfed` 21 (all `case=ring shape=exit`, `turbo=true`, exit-only junctions of rings with splitter arms, e.g.
  ring 8330: 4 lanes, 6 arms): the lane is the ring-out outer lane. Turbo makes the outer ring lane exit-only,
  so after a junction with no entry nothing feeds it up to the next entry, which joins it without giving way
  (the point of the turbo layout). Now `forced=turbo_gap:1`, by design; any other unfed lane there is still
  `unfed`.
- `bypassed_turn` 4 (T-junctions 117874 and 123825, side road `k|f`): both turns into the side road have slip
  lanes, so the crossing rule keeps both (it never leaves an exit road unfed: a building or stop along that
  street side would only be reachable with a U-turn). The audit counted each kept turn as "the other feed".
  It now flags a bypassed turn only when the exit road has another kept feed that is not itself a bypassed
  turn and the approach has another exit that is no bypassed turn (as sl_cross dropBypassed, which never
  drops every exit of an approach). The game default at a Channelized X still flags its 4.
- `weave` 16630 (1957 junctions, almost all town grid crossroads / T-junctions with `k|s|sf` approaches): into
  each 3-lane exit road, the curb turn lands in the curb lane, a turn-only lane at the next crossroads one block
  on (misses 2), straight lands in lanes 2-3 (misses the curb turn), the far turn in lane 3 (misses 1): 4 per
  exit road, 16 per crossroads. Inherent to short blocks with dedicated curb turn lanes: every lane of the exit
  road is fed, and putting a movement on another lane would cross or share with another movement. Now only the
  misses that free lanes (nobody feeds them) next to the movement's lanes would cover are avoidable (`weave`);
  the rest is `forced=weave:n`. The rule's own output therefore never flags `weave`; game defaults and hand
  edits that leave an exit lane empty still do.

Expected now from the same run: ramp_ramp 0, unfed 0 (turbo_gap 21 under forced, "by design" in `make audit`),
bypassed_turn 0, weave 0 avoidable (~16630 forced); the AUDIT lines shrink from ~2064 to the few junctions with
other findings.

Checks in game:
1. Repeat the Showcase (any seed), then `make audit ARGS='--last --src auto'`: no ramp_ramp at `case=ring`, no
   unfed at `case=ring shape=exit` on turbo rings, `turbo_gap` listed under totals as "by design", `weave` only
   in the forced column. Anything left under "Findings by type" is a real candidate: select it with the tool.
2. A turbo ring with splitter arms (Roundabout, splitters On, 2+ lanes): in the lane view the outer ring lane
   between an exit leg and the next entry leg has no connection in from the ring; the entry leg's curb lane
   joins it. Watch traffic: entering cars do not wait there.
3. T-junction 117874 / 123825 type (a side road served by slip lanes from both main road directions): both
   turns into the side road remain at the T (APPLY `k|...` and `...|sf`), and pick it with the tool: no
   `bypassed_turn`.
4. Open question for a rule decision (not changed): in a grid of 3-lane streets with blocks of 80 m or less,
   curb turners land in the next crossroads' curb turn lane and must change lanes within the block to go on.
   Letting that curb lane also go straight (`ks|s|sf`) where it is fed by a turn from a junction less than 80 m
   back would remove 2 forced weaves per exit road, at the price of a shared exit lane further on.

Unit tests: test_audit.lua "showcase: ..." (a highway-road interchange ring, both directions and traffic sides:
no ramp_ramp at the arms, still flagged without the ring; a turbo ring with three splitter arms: turbo_gap at
each exit node, unfed when the outer lane continues and the ring-out outer lane is still left empty; a T with
slip lanes from both main road arms into the side road: both bypassed, both kept, no bypassed_turn, the
Channelized X game default still 4; "bypassed_turn: an approach whose every exit is a bypassed turn keeps
them"; two 3-lane grid crossroads 60 m apart: `forced.weave` 4 per node, none
avoidable), "weave (heuristic)" (the rule's link lanes: forced; a lone curb turn with the link's far lane free:
avoidable 1), tests/tools/test_sqrl_audit.py ForcedKindsTest.

## FK. Free curb turn at traffic lights (rev 4, setting "Free curb turn at traffic lights": Off / When safe / Always; sl_lights.lua L.kerbPhases)

What it does: at every crossroads / T-junction (sl_cross case X) that Smart Lanes writes, the curb turn connections
(right in right-hand traffic, left in left-hand traffic; `X.kerbPairs`, road connections only, tram connections
untouched) are taken out of phases' `lockedLanes`, in the same proposal as the lanes (`W.remapLights` after
`Rules.remapLocked`; curb turns freed earlier are locked back with their approach first, then freed again):
- **When safe** (`L.SAFE`): only in a phase where nothing green conflicts (`L.kerbConflict`): no green
  connection of another approach (road or tram) ends in the turn's exit lane (merge) or in a lane of the exit nearer
  the curb (cross: the turner would cut across it; lanes farther out run beside it), and no green crosswalk on the
  approach or the exit road (ped; a crosswalk entity that is none of the node's roads counts as a conflict). The
  approach's own movements never conflict. Phases where the turn is already green stay.
- **Always** (default since 2026-10-12, user decision; `L.FREE`): every phase (the old On).
- **Off**: no phase change from this feature at all (phases only re-pointed for new lanes).
- **Since rev 8** (section SH): When safe and Always free only a curb turn whose entry lane turns and nothing else
  (`L.sharedKerb`); one sharing its lane with a straight or far turn (every 1- and 2-lane road with Smart Lanes'
  lanes) stays red with its lane (`shared_held=<n>` on the lines below). The checks of this section need 3-lane roads
  (a dedicated curb lane) since then.

Crosswalk indices and the phases (count, durations) stay; a phase left with nothing red stays. Lanes already
right: one phases-only light proposal (`W.kerbLights`, the base phase editor's
`createTrafficLightProposal(node, clone, pref)`), only where a light stands and something changes. Reset (tool)
locks the curb turns back where every other connection of their approach is red (the game's default; `L.LOCK`).
Nodes whose lights Smart Lanes removes (ring arms, slip diverge / merge, case A / B) and lane drops (D) are not
touched. Curb turns a slip lane serves (section R) have no connection at the centre, so there is nothing to free.

What to expect (since 2026-10-12, user decision: merges allowed, PLAN.md "When safe allows merges"): a curb turn
into a road whose straight traffic has green merges with it and goes too (`merge_free=` counts those pairs); it
stays red only where a green stream ends curbward of its exit lane (`kept=cross:..`) or a crosswalk on the two
roads it drives over has green (`kept=ped:..`; with the game's phases the crosswalks are often green with the
crossing road, so that is the usual reason left).

Log: `SUMMARY ... free_turn=<curb connections unlocked in at least one phase> free_phases=<(connection, phase)
unlocks> kept=<cross:n,ped:n: (connection, phase) pairs When safe kept red, first kind only> merge_free=<pairs freed
while a green stream ends in the same lane>` (`free_turn=off` with the setting Off; no kept= with Always); the tool's
`WRITE ... free_turn=<n> free_phases=<n> [kept=.. merge_free=..]` / Reset
`lock_turn=<n> lock_phases=<n>`; phases-only `LIGHTS src=auto|tool|reset|recheck node= to=free_turn|lock_turn
free_turn|lock_turn=<n> states=<phases> pref= user_modified=<cfg.userModifiedTrafficLightStates>
free_phases|lock_phases=<n> [kept=.. merge_free=..]`; re-checks `RECHECK kind=free_turn job= nodes= phases= locked= sent= changed=`
(When safe: `locked=` also counts turns kept red on purpose; `sent=0` then).

Checks (year 1950+, right-hand traffic first, then a left-hand traffic game):
1. **When safe: does a freed turner ever cut across green traffic, or meet green pedestrians?** Build a lit
   2x2 crossroads, a lit 3x3 crossroads and a lit T-junction of town roads in a busy town. Note the SUMMARY's
   `free_turn= free_phases= kept= merge_free=`. Open each junction's Crossing window and step through the Phase #N
   boxes: a green curb turn curve may share its exit lane with another green curve (a merge, allowed since
   2026-10-12) but never cut into it from a lane nearer the curb, and no crosswalk on its two roads is green then.
   Fast-forward and watch 3-5 minutes per junction:
   a. turners merging with straight / far-turn traffic that has green into the same lane: does it flow (as on the
      showcase, 2026-10-12), or do they collide / jam at busier junctions?
   b. turners vs. pedestrians on the crosswalks of the road they leave and the road they enter: does any
      pedestrian have green while the turn is free?
   c. does anything deadlock (vehicles stuck inside the junction)?
   d. Edit one junction's phases by hand to one phase per approach, then Apply to junction (tool): the LIGHTS line
      should free each curb turn in every phase (`free_phases=` > 0, `merge_free=` > 0 for the phases of the
      straight into its exit), and the phases still never show a crossing green.
   e. **Crosswalk mapping probe**: on one junction compare `cfg.crosswalks`
      (`api.engine.getComponent(node, api.type.ComponentType.BASE_NODE_CONFIG).crosswalks`) with the node's
      segments (`api.engine.system.streetSystem.getNode2SegmentMap()[node]`) and with the Crossing window (which
      crosswalk index is drawn on which road). Expected: the entries are the node's edge ids. If not, every green
      crosswalk keeps every curb turn red (`kept=..ped:..` high, `free_phases=0`): note it in findings.md.
2. **Always vs When safe**: set Always, build the same junctions: every curb turn curve green in every phase
   (`free_turn=<n> free_phases=<n>`, no kept=). Turners driving into green straight traffic without giving way
   (findings.md 2026-10-12) is the expected Always behaviour; record whether it drives through other vehicles or
   jams, to confirm Always as the default (user decision 2026-10-12; When safe is the fallback).
3. **Persistence after a nearby build**: build a road touching another node of one of the junction's roads (not
   the junction), then upgrade one of its roads (street upgrade tool), then add a fourth arm to the T. After each:
   Crossing window phases. Expected: the untouched junction keeps its freed turns; a build that touches the junction
   starts a job and logs `SUMMARY ... free_turn=` again (or a `LIGHTS src=auto ... to=free_turn` line where the
   lanes were already right and something changes). Note `user_modified=` in those LIGHTS lines, and whether the game
   ever re-locks the curb turn without a Smart Lanes line (= it regenerated phases on its own: findings.md).
4. **AUTO lights that come after the read**: build crossroads and watch for `RECHECK kind=free_turn`: about 1 s and
   10 s after the write, for nodes whose light state was unknown at the read (`lit=unknown` on the APPLY line).
   `sent=1` = the game put lights / phases there after our write and they were freed then (LIGHTS src=recheck);
   `phases=0` = still no phases after 10 s (lights that come later than that stay locked: note how long they take).
5. **Save / reload**: the freed phases stay (Crossing window after loading).
6. **Tool**: Apply to junction on an old lit crossroads: `WRITE ... free_turn=<n> free_phases=<n> kept=..`. Apply
   again after the game re-made the phases: `LIGHTS src=tool ... to=free_turn`, no lane write. Reset:
   `WRITE src=reset ... lock_turn=<n>`, the Crossing window shows the game's phases again (curb turn red with its
   approach). Street / multi Apply and Reset log the same fields per batch.
7. **Setting Off**: a new crossroads keeps the game's phases (`SUMMARY ... free_turn=off`, no LIGHTS to=free_turn
   lines); the tool's Apply keeps them too; Reset still locks back curb turns freed earlier.
8. **No crash**: a lit 3x3 crossroads rebuilt from 36 to 16 connections (the 2026-10-11 crash case) with each of
   the three values: no `VectorMap.h` assert, `ERROR` lines none. The Channelized X / T centre: `free_turn=0` there
   (its curb turns are slip lanes).

If it fails (When safe still frees a turn into conflicting traffic or pedestrians): note the junction, the phase and
the two curves and fix `L.kerbConflict` (When safe is not the default: Always is, since 2026-10-12). If Always
proves harmful, set the default When safe or Off (mod.json `defaultIndex` 1 / 0, `Rules.DEFAULTS.freeTurn` 2 / 1,
update test_rules "mod params" and the description). If crosswalk entities are not edge ids, map them another way in
`L.kerbConflict` (or keep the conservative rule: any green crosswalk blocks).

Unit tests: test_lights.lua "kerbPairs" / "kerbIndices" / "kerbPhases" (FREE / LOCK) and "kerbPhases SAFE: ..."
(X with one phase per approach and T with the game's phases, both traffic sides: kept red under the green straight
into its lane, freed elsewhere; green crosswalk on A / E / another road / unmapped; lane order merge / cross /
beside, trams, no order = conservative, two curb turns into one lane; stale input, already green, empty phases);
test_script.lua "free turn: ..." (Always: lane write in one proposal, relock path, phases-only, stale phases,
re-checks; Off = plain re-pointing) and "free turn When safe: ..." (one phase per approach, the game's two phases,
green crosswalk, relock + phases-only LIGHTS fields, stale / Off); test_tool.lua "free turn (tool): ..." (Always
and Off) and "free turn (tool) When safe: ..." (Apply / Reset, two phases vs Always, street batch).

## LP. Light phases probe: what the game's default phases look like (PHASES_PLAN.md step 0, sl_write W.probePhases)

Read-only: nothing is sent. With **Debug: performance log** On, every lit node Smart Lanes reads (the automatic pass
after a build: every job node off a ring; the tool: every junction you click or Shift+click) is dumped once per
node and Lua state (the automatic pass and the tool each log a node once), at most 200 nodes each. A node without a
light and without phases is not logged and is logged on a later read once its light came (AUTO lights can come
later). Lines (all match `grep "PROBE phases"`):
- `PROBE phases node= type= pref= user_modified= user_lanes= states=N durations=<per phase> min=<minDuration per
  phase> skip=<canSkip per phase> conns=N arms=A=<segment>@<deg>,... crosswalks=<entities> cw_is_edge=y|n,...
  light=true|false light_state= light_time= state_times= data_durations= data_locked=<count per phase> data_same=
  data_red= data_models=`. Arms are lettered counter-clockwise by the direction away from the node (0 deg = +x);
  `cw_is_edge=y` = that crosswalk entity is one of the node's segments. `data_*` = `BaseNodeTrafficLight.trafficLightData`
  (`data_same=true`: its `state2lockedLanes` equal the config's phases).
- `PROBE phases_conns node= part=i/k list=A1>B4,...`: the connections in config order (index 0 first): arm letter +
  lane index of segment0 `>` segment1; suffix `t` = with tram, `x` = no road; `?<segment>` = not at the node.
- `PROBE phases_state node= state=i part=i/k duration= min= skip= n=<locked count> locked=<0-based indices>`: indices
  below `conns` are connections, `conns + k - 1` is crosswalk k.

Questions it answers (results go to findings.md "Traffic light phase records, units and defaults"): the duration
values and their unit (seconds expected), whether `minDuration` / `canSkip` are set by default, what `type=`
values occur, whether yellow or all-red appear as separate phases (a phase with `n=` = conns + crosswalks is
all-red), whether crosswalk entities are the node's edge ids (`cw_is_edge`), the default phase structure at T and X
junctions with and without turn lanes (which connections share a phase), and whether `trafficLightData` mirrors the
config.

Steps (year 1950 or later; right-hand traffic first, then one left-hand traffic game for 2 and 4):
1. Mod settings: **Debug: performance log** On (set it before loading; the probe gate is read with the SQPERF
   window). **Free curb turn at traffic lights: Off** (so Smart Lanes frees no curb turn and the phases stay the
   game's own, only re-pointed to the new lanes). The automatic pass dumps a node before its own lane write (the
   game's phases on the game's connections); a tool click on a node Smart Lanes already wrote shows its phases
   re-pointed to Smart Lanes' connections. A light the game adds after the build (AUTO) is dumped at the click.
2. In a town, build with town roads, each as a fresh junction, and wait ~10 s after each build:
   a. 2x2 crossroads (medium x medium);
   b. 3x3 crossroads (large x large);
   c. 3x3 x 2x2 crossroads (large main road, medium side road);
   d. T-junction of medium roads; e. T-junction of large roads;
   f. 1x1 crossroads (small x small);
   g. a crossroads where one arm is a one-way street (into the junction) if the town allows it;
   h. a crossroads of tram roads (medium tram) if available.
3. Open the Smart Lanes tool and click each of those junctions once, plus two old town crossroads the game built
   itself (preferably one T and one X). The tool logs the ones its state has not logged yet.
4. For junction a: open the base Crossing window (click the junction), step through the Phase #N boxes and note per
   phase which curves are green and which crosswalks (drawn on which road) are green, and the Duration / Allow
   Skipping / Min. Duration values shown. This ties the logged indices to what the window draws.
5. Note the light colours during a phase change at junction a (is there an amber moment, an all-red moment, and
   about how long).
6. Paste back: `grep "PROBE phases" stdout.txt` (the whole output; it is bounded), plus the notes from 4 and 5, and
   which junction (a-h, old town) each `node=` is (the tool's PICK line has the node id).
7. For the phase planner (PHASES_PLAN.md "Open"), at junction a with pedestrians around: when a turning car has green
   together with the crosswalk it crosses (the game's default does this), does it stop for people on the crosswalk,
   or drive through them? And does a phase with "Allow Skipping" get skipped while pedestrians wait at its crosswalk
   (tick it on one phase in the Crossing window and watch a few cycles)?

Expected: `ERROR where=probe_phases` none; nothing else changes (no LIGHTS / WRITE lines from the probe).

## LS. Light phases = Smart Lanes: planned phases written with the lanes (rev 4, PHASES_PLAN.md step 4; sl_phaseplan.lua, sl_write W.remapLights / W.planLights / W.defaultLights)

Default is **Game default** (nothing changes). With **Smart Lanes**, a lit crossroads or T-junction that Smart Lanes
handles gets a planned phase set in the same proposal as its lanes: only movements that neither cross nor merge are
green together (far turns get their own arrow or their approach's own phase), crosswalks beside parallel traffic or
in a pedestrian phase, an all-red clearance after every phase (2-4 s, 3 s after the pedestrian phase), every phase
but the all-reds skippable (min 1.5 s, as the game). Greens 15 s + 4 s per lane (19 / 23 / 27 s), cycle scaled into
40-90 s. Offline examples (RHT, crosswalk on every arm; `make test MOD=mods/square_smart_lanes -f test_phaseplan`
prints them): 2x2 X `x4_split` 4 x 16 s + 2 s red, walk 15 s + 3 s red = 90 s (75 s with the walk phase skipped);
3x3 X `x4_split` 4 x 23 s (crosswalk beside each approach) + 3 s red = 104 s; 2x2 T `t3` 23 / 19 / 19 s + 2 s reds,
walk 15 s + 3 s = 85 s. The game: 6 phases, 71-78 s.
**Since rev 8 the default is the axis plan (section AX)**: crossroads and T-junctions get `x4_axis` / `t3_axis` (one
phase per road, a 6 s pedestrian phase after each, no all-reds); the plans above are the classic patterns, made
inside an `sl_classic` zone until 2026-10-16 (removed since: section NC).

Log lines:
- `[SQRL] MODE phases=game|sl free_turn=off|safe|always` once per load (FLOW.md).
- `PHASES src=auto|tool|reset node= phases=sl plan=<kind cycle= i:<d>s[/skip<min>][<green>] ... i:red<d>>` or
  `plan_fail=<reason>` (unlit, lit_unknown, no_phases, invalid_*, map_*, crosswalks, error:...): one per planned node.
  In `plan=`, green entries are connection indices (config order) and `w<k>` crosswalk k; `red<d>` an all-red.
- `WRITE ... phases=game|sl` (+ `sl_plans= plan_fails=` for the automatic pass and street / multi batches, `plan=` /
  `plan_fail=` for one-node tool writes); `SUMMARY ... phases=sl sl_plans= plan_fail=<reason:count> free_turn=..`.
- Lanes already right: `LIGHTS src=auto|tool|recheck node= to=sl_phases phases=sl states= cycle= pref= user_modified= plan=`.
- Unknown light at the build: `RECHECK kind=phases job= nodes= phases= sent= same= fail= changed=` at ~1 s and ~10 s.
- Reset (Smart Lanes mode): `LIGHTS src=reset node= to=game_phases phases=game states=<before>` after the lane write.

Steps (1950 or later, town roads; right-hand traffic, then one left-hand traffic game for 2-4):
1. Mod settings: **Light phases: Smart Lanes**, Free curb turn: When safe (not the default), Debug: performance log On.
   Load; `grep "SQRL] MODE"` shows `phases=sl free_turn=safe`.
2. Build fresh lit junctions, ~10 s apart: a. 2x2 X (medium x medium), b. 3x3 X (large x large), c. 3x3 x 2x2 X,
   d. T of medium roads, e. T of large roads. For each: `PHASES src=auto node=N phases=sl plan=...` or
   `plan_fail=lit_unknown` followed by `RECHECK kind=phases ... sent=1` and `LIGHTS src=recheck to=sl_phases`.
   No `ERROR`, no `VectorMap` assert or "Exception during simulation loop" in stdout.txt (crash rule).
3. Click each junction (base Crossing window): the Phase #N boxes match the `plan=` text: the same number of phases,
   durations (Duration slider), "Allow Skipping" ticked on every phase but the all-reds (min 1.5 s), all-red phases
   with the greyed X icon, green curves = the listed indices (index order = the window's lane order). Note any phase
   whose green curves cross or meet in one exit lane (must be none).
4. Watch traffic for a few cycles at a and d: no left turn (right turn in LHT) moving while the oncoming straight has
   green; turners into one lane never from two approaches at once; pedestrians cross only on their green and are not
   cut off (a phase must not end while people are on its crosswalk: "skip" with them on it would be a finding);
   the pedestrian phase is skipped when nobody waits; the all-red phases actually run (all lamps red ~2-3 s).
5. Persistence: build a road next to junction a (a new arm elsewhere on one of its roads, not at the node) and
   upgrade one of its roads; click it again: are the phases still the plan (`PROBE phases` with Debug On, or the
   Crossing window), or did the game re-make its six phases? (findings.md "regeneration" open point.)
6. Tool: select junction a, Apply to junction: `already set` and no LIGHTS line (the plan stands). Reset: WRITE
   src=reset, then `LIGHTS src=reset to=game_phases`; the Crossing window shows the game's six phases again (the
   engine made them from `states = {}`; if the window shows no phases or the junction has no lights now, that is a
   finding: note it). Apply to junction again: the plan comes back (WRITE `plan=`).
7. Street: click the road between a and another lit crossroads, Apply: WRITE `sl_plans=2`; Reset: two
   `LIGHTS src=reset to=game_phases` lines.
8. Back to **Game default**, reload: `MODE phases=game`. Build a new crossroads: no PHASES lines, its Crossing window
   shows the game's six phases (free curb turn as set). Junctions written before keep their planned phases until
   the tool's Reset with Smart Lanes, or the Crossing window's Reset to Default.
9. Paste back: `grep -E "SQRL\] (MODE|PHASES|LIGHTS|RECHECK|SUMMARY|WRITE|ERROR)" stdout.txt`, the notes from 3-6 and
   screenshots of the Crossing window at a (two phases) and d.

Expected: every planned phase conflict-free in the window, no crash, no ERROR; Reset gives the game's phases.

## ZN. Zones from other mods: game / sl / sl_phases (rev 4, sl_zones.lua; 2026-10-12, not run in game yet)
Background: FLOW.md "[SQRL] ZONES" (plans/square_stress_test), Stress Test TESTING.md 6O (the Showcase sends the
zones). Settings at defaults (Light phases: Game default). Needs the Stress Test Debug Tool (rev 2) and
Roundabouts & Interchanges for the Showcase.
1. Load any save: one `[SQRL] ZONES op=loaded n=0 run=-` right after `MODE` (also with Apply automatically Off).
   An **old save** (made with Smart Lanes before this change, so subscribed to onPostBuildProposal only): the
   Showcase's zones still arrive (`ZONES op=set` in step 2): the per-load re-subscribe works.
2. Stress Test, Towns tab, Build showcase: `[SQRL] ZONES op=set n=.. run=.. by_ab=game:..,sl:..,sl_phases:..` before
   the first Showcase junction's APPLY lines; the Stress Test's `zones ack=yes`.
3. Game twins (`ab=game`): the game's lanes and lights; `SKIP kind=zone zone=game job= nodes= reason=zone_game` per
   job, `SUMMARY ... skips=zone_game:N`. sl twins: Smart Lanes lanes as usual. sl_phases twins (lit plain
   crossings): `PHASES ... phases=sl plan=` and `SUMMARY ... zone_phases=1` although Light phases is Game default;
   their Crossing window shows the planned phases (twin b next to it: the game's six).
4. Save and reload: `ZONES op=loaded n=<same> run=<same>`; a new crossroads inside a game twin's circle is left alone,
   one inside an sl_phases circle gets planned phases.
5. Tool: Apply to junction at a game twin works; its `APPLY src=tool` line ends in `zone=game`. Apply to junction at
   the sl_phases twin (g3c) with Light phases = Game default: `WRITE ... phases=sl plan=` / `PHASES src=tool ...
   phases=sl` (the tool plans phases in an sl_phases zone too); Reset there gives the game's phases back.
   Pick a node that reads `conns=0` (a one-way road's continuation, a dual carriageway split): `PICK ... findings=-
   skipped=no_config:1` (or `config_error:1` if the read threw), no AUDIT dead/unfed lines.
6. Stress Test Remove all roads: `ZONES op=clear n=0`; reload: `ZONES op=loaded n=0`.
7. No crash, no `ERROR`, no `gamescript_util.cpp` assert (the zones are read with state:get only). Paste back:
   `grep -E "SQRL\] (MODE|ZONES|SKIP kind=zone|SUMMARY|PHASES|ERROR)" stdout.txt`.

## FN. Fan mode: zone `sl_fan` (rev 4, PHASES_PLAN.md "Fan mode"; sl_cross X.fanConns, sl_phaseplan opts.fan; 2026-10-12, not run in game yet)
Background: the user's hand-made lit crossroads (every lane to every lane, the light does the rest), built to be
**measured** against the game / sl / sl_phases twins. The Stress Test does not send `sl_fan` zones yet (its
`SL_ZONE_AB` lists game / sl / sl_phases): until it does, send one by hand from a debug console or a DEV probe
(`api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.zones", { op = "set", run = "fan1",
zones = { { x = .., y = .., r = 60, ab = "sl_fan" } } })`). A set replaces every zone: send the Showcase's list plus
the fan circles. Settings at defaults.
1. `[SQRL] ZONES op=set n=.. run=.. by_ab=game:..,sl:..,sl_phases:..,sl_fan:N` (`sl_fan:` only when N > 0).
2. Build a lit 2x2 crossroads (traffic lights YES) inside the circle: one proposal; `APPLY kind=slip node=.. case=X
   ... lit=yes mode=fan`, `PHASES src=auto node=.. phases=sl plan=x4_fan cycle=90 ...` (4 approach phases, all-reds,
   the walk phase), `SUMMARY ... zone_fan=1`, no `AUDIT` line for it. NodeViewer: every entry lane fans to every exit
   lane of the three other roads (2x2: 48 connections). Crossing window: 4 approach phases + pedestrian phase, each
   approach's whole fan green alone (plus at most a turn into its own road from another approach), 2 s all-reds.
3. A lit 3x3 and a lit T in the circle: `plan=x4_fan` (108 connections) / `plan=t3_fan` (24 at a 2x2 T). Left-hand
   traffic map: the same kinds and phase counts.
4. An unlit crossroads (lights NO) in the circle: the rule's lanes, `APPLY ... lit=no fan=unlit`, no PHASES plan.
   AUTO before 1950 / no light yet: `fan=lit_unknown`; if a light comes later, `APPLY src=recheck ... mode=fan` and
   `RECHECK kind=phases ... sent=1` within 600 frames.
5. Tool inside the circle: Apply to junction at a lit crossroads writes the fan + `PHASES src=tool ... plan=x4_fan`;
   the badge reads "Smart lanes"; the same lanes outside any fan circle read "Custom". Reset: the game's lanes and
   default phases.
6. Traffic (the measurement): run the Stress Test traffic for a few in-game months with a fan twin next to the game /
   sl / sl_phases twins; compare the traffic log's throughput and queue numbers (FLOW.md). Watch: do vehicles merge
   into one exit lane from two entry lanes and stall inside the junction? Do they pick the inner lanes for far turns?
7. No crash, no `ERROR`, no `SKIP ... reason=lights:fan_..` (a fan whose plan failed; the node then keeps its lanes).
   Paste back: `grep -E "SQRL\] (ZONES|APPLY.*(mode=fan|fan=)|PHASES|SUMMARY|RECHECK|SKIP.*fan_|ERROR)" stdout.txt`.

## FL. Lock mode: zone `sl_lock` (rev 4, PHASES_PLAN.md "Lock mode"; 2026-10-12, not run in game yet)
Background: the free curb turn measured on its own: the Stress Test's Lights showcase builds an `sl_lock` twin (Smart
Lanes lanes, curb turn never freed, game phases) next to the `sl` twin (the global settings, Free curb turn =
Always). Settings: Free curb turn Always, Light phases Game default.
1. `[SQRL] ZONES op=set n=.. run=.. by_ab=game:..,sl:..,sl_phases:..[,sl_fan:..],sl_lock:N` (`sl_lock:` only when N > 0).
2. Each sl_lock twin's crossroads / T: one proposal; `APPLY kind=slip node=.. case=X ... zone=sl_lock free_turn=off`,
   no `PHASES` line, `SUMMARY ... zone_lock=1 lock_turn=0 lock_phases=0 free_turn=..` (a fresh junction: nothing
   to lock back). Crossing window: the curb turn red with its approach (as the game's twin); the `sl` twin next to
   it: the curb turn green in every phase. Its `AUDIT` line (if any) ends in `zone=sl_lock free_turn=off`.
3. Re-apply: with the twins built, send the zones again with an sl circle turned sl_lock (or Apply to junction at an
   sl twin first, then move it into an sl_lock circle and rebuild a road there): the freed curb turns end red again,
   `SUMMARY ... lock_turn=<n> lock_phases=<n>` (lane write) or `LIGHTS src=auto ... to=lock_turn lock_turn=<n>`
   (lanes already right).
4. Tool inside an sl_lock circle: Apply to junction writes `WRITE ... lock_turn=.. phases=game`, `APPLY src=tool ...
   zone=sl_lock free_turn=off`; the curb turn stays red.
5. Traffic: `make flow` shows `sl_lock vs game` and `sl vs sl_lock` rows per lit crossing set.
6. No crash (lockedLanes index asserts, VectorMap.h:11), no `ERROR`. Paste back:
   `grep -E "SQRL\] (MODE|ZONES|APPLY.*sl_lock|LIGHTS.*lock_turn|SUMMARY|AUDIT.*sl_lock|ERROR)" stdout.txt`.

## EF. Exit-lane fan: zone `sl_exitfan` (rev 4, PLAN.md "Exit-lane fan (sl_exitfan zones)"; 2026-10-13, not run in game yet)
Background: the exit-lane fan measured on its own, as a twin next to `sl` (sl vs sl_exitfan = the fan alone; Light
phases Game default, Free curb turn as set, ideally Always). Outside an sl_exitfan circle nothing changes.
1. `[SQRL] ZONES op=set ... by_ab=game:..,sl:..,sl_phases:..[,sl_fan:..][,sl_lock:..],sl_exitfan:N` (only when N > 0).
2. Each sl_exitfan twin's lit crossroads / T: one proposal, `APPLY kind=slip ... lit=yes exit_fan=yes ... zone=sl_exitfan`,
   no `PHASES` line, `SUMMARY ... zone_exitfan=<n> exit_fan=<n>`. Crossing window (2x2): each approach's curb turn
   into both lanes of its exit, the far turn into the far lane only, straights lane to lane (20 connections; the `sl`
   twin 16, the game's 24). 3x3: curb turn into exit lanes 1-2, far turn 2-3, the lane strings `k|s|sf` as `sl`.
3. Phases (Free curb turn Always): the curb turn's connection into the exit's curb lane green in every phase, its
   connection into the far lane red with its approach (the Crossing window's phase boxes). No `VectorMap.h:11` crash.
4. Unlit / AUTO without a light: `exit_fan=unlit` / `exit_fan=lit_unknown` and today's lanes; a light that comes later
   within 600 frames: `APPLY src=recheck ... exit_fan=yes`, `WRITE kind=exit_fan node=.. success=true`.
5. Tool inside the circle: Apply to junction writes the fan (`APPLY src=tool ... exit_fan=yes zone=sl_exitfan`, `WRITE
   ... phases=game`); the badge reads "Smart lanes" there and "Custom" for the same lanes outside.
6. Audit: no `shared` findings from the fan (`shared_lit` in the forced counts).
7. Traffic: `make flow` rows `sl_exitfan vs sl` and `sl_exitfan vs game` per lit set. Paste back:
   `grep -E "SQRL\] (MODE|ZONES|APPLY.*exit_fan|WRITE.*exit_fan|SUMMARY|AUDIT.*exitfan|ERROR)" stdout.txt`.

## BN. Stress Test bench additions (SL-1 .. SL-6; 2026-10-13, not run in game yet)
Background: plans/square_stress_test/BENCH.md "As implemented in Smart Lanes". With the bench's mini sheet:
1. `[SQRL] MODE ... lights=on`; `ZONES op=set ... by_ab=...,sl_keeplights:<n>`.
2. sl_keeplights (letter f) twins: `LIGHTS src=auto node=.. to=kept zone=sl_keeplights zid=g<k>f` at every ring arm /
   slip node, the lights stand in game; sl twins: `LIGHTS ... before=auto` and no lights; `SUMMARY ...
   zone_keeplights= lights_kept=`.
3. `zid=` on every APPLY / LIGHTS / AUDIT line of twin nodes, `SKIP kind=zone ... zid=` for game twins.
4. The game-script state (the bench's preflight) has `zmodes` and, after a refused payload, `zerr`; `qlen` falls to 0
   about 10 s after the last build.
5. ~600 frames after the lights-off: `RECHECK kind=lights ... lit=0 queued=0` per entry (lit > 0 means a light came
   back and was switched off again). No crash, no `ERROR`.

## RV. Ring layout variants: zones `sl_rturbo` .. `sl_rspread` (PLAN.md "Ring layout variants (bench)"; 2026-10-13, not run in game yet)
1. `ZONES op=set ... by_ab=...,sl_rturbo:<n>,...` (each variant only when present, after `sl_keeplights`).
2. Every arm junction of a twin ring: `APPLY ring=.. node=.. ... layout=<mode> zid=<id>`; `SUMMARY ... zone_ring=1`.
   Crossing window: the connections of PLAN.md's table (e.g. sl_rout1: only the outer lane leaves, into every exit lane;
   sl_rspiral: inner lanes shift one lane outwards at each exit junction).
3. After the links and town growth: no further APPLY on those rings (`SKIP kind=ring ... reason=same` only); the
   Crossing window still shows the variant (no flip to matched, unlike the `sl` twins).
4. Traffic: no stuck vehicles at any variant ring (every destination reachable; sl_rspiral needs no lane change); no
   `ERROR`, no crash. Paste back: `grep -E "SQRL\] (ZONES|APPLY ring=.*layout=|SUMMARY.*zone_ring|ERROR)" stdout.txt`.

## RS. Mid-node spiral: zones `sl_rsplit` and `sl_rmid` (PLAN.md "Mid-node spiral (sl_rsplit)", "Mid-node lane changes (sl_rmid)"; 2026-10-14: sl_rsplit steps 1-3 seen in game in Sheet 4 v3 (mids=4, mid=yes after=3, VERIFY same=8 nodes=8), sl_rmid not run yet)
Run Stress Test Bench > Sheet 4 (v3: ring `bench_rb2tm`, twins game `s4g1b`, sl `s4g1a`, sl_rspiral `s4g1l`, sl_rsplit
`s4g1n`). The decisive lines (paste back: `grep -E "BENCH_TWIN|SQRL\] (RSPLIT|APPLY .*mid=yes|WRITE ring|VERIFY ring|ERROR)"
stdout.txt`, or `make logs-grep PAT='RSPLIT|mid=yes|VERIFY ring'`):
1. The mid nodes were built: every twin `BENCH_TWIN ... geometry=ok what=one_way_streets n=8 mids=4` (8 one-way ring
   edges, 4 nodes joining two one-way streets only). `mids=` under 4 or `geometry=bad`: square_roundabouts without the
   dev override (old staging copy) or the game merged the nodes.
2. Smart Lanes found them: one `RSPLIT ring=<key> node=<key> mids=4 nodes=<4 ids> zid=s4g1n` (`mids=0 fallback=sl_rspiral
   reason=...`: it did not, and the twin is excluded by `make bench`).
3. **The game accepts the lane change at a 2-edge node**: 8 `APPLY ... layout=sl_rsplit zid=s4g1n` (4 junctions
   `before=4 after=4`, 4 with `exits=0 entries=0 ... before=2 after=3 ... mid=yes`), then `WRITE ring=<key> nodes=<8 ids>
   success=true` and `VERIFY ring=<key> same=8 nodes=8`. `success=false` or `same=` under 8 (which nodes: the VERIFY
   detail) means the game refuses or rewrites such a node: a finding for docs/findings/roads.md either way.
4. The other twins: no `mid=yes` and no `RSPLIT` line with their zid; `s4g1l` APPLY `layout=sl_rspiral` at the 4
   junctions only.
5. (The Crossing Tool can't pick a mid node, seen in game 2026-10-13: docs/findings/roads.md; the mid nodes' lanes are
   proven by the APPLY `mid=yes after=3` and VERIFY `same=8` lines only.) On `s4g1n` a mid node has 3 connections: outer lane
   straight, outer lane into the inner lane, inner lane straight; an arm junction 4: outer lane into the exit only, inner
   lane into the outer lane and straight on, the entry into the outer lane only. On `s4g1l` and `s4g1b` the mid nodes
   show 2 straight curves (the game's). No crash on clicking a mid node (NodeViewer `edgeIdx` guard, findings).
6. Do cars use it (only visible, no log line): at 2x, watch `s4g1n` for 1-2 minutes: cars entering an arm stay in the
   outer lane to the next exit, or move to the inner lane at the mid node (the red circles of the user's screenshot);
   inner-lane cars move out at the junction. Nobody circles forever, nobody stops at a mid node, no queue at an entry
   that `s4g1l` doesn't have. Then `make bench`: rows `sl_rsplit vs sl_rspiral` and `sl_rsplit vs game` (one pair each:
   a direction, not significance).
7. **sl_rmid** (Sheet 4 v4, twin `s4g1o`, PLAN.md "Mid-node lane changes (sl_rmid)"): one `RSPLIT ... mids=4 nodes=<4 ids>
   zid=s4g1o`; 8 `APPLY ... layout=sl_rmid zid=s4g1o`: 4 junctions `after=3` (outer lane into the exit only, inner lane
   straight only, the entry into the outer lane only), 4 mid nodes `exits=0 entries=0 ... before=2 after=4 ... mid=yes`
   (both lanes straight plus outer -> inner and inner -> outer, crossing at the node); then `WRITE ring=<key> ...
   success=true` and **`VERIFY ring=<key> same=8 nodes=8`: the engine keeps two crossing lane changes at a 2-edge node**
   (`same=` under 8 or `success=false`: it does not; a finding either way). Traffic (visible only): cars bound for the
   next exit leave the inner lane at the mid node, nobody changes lanes at an arm; watch for cars stopping at a mid node
   (yielding between the two crossing lane changes) or circling.

## LU. Ring lane use: zones `sl_rmid2` and `sl_rturbo_in` (PLAN.md "Ring lane use (in progress)"; 2026-10-15, offline only, not run in game yet)
Run it as the Stress Test's bench Sheet 5 (plans/square_stress_test/TESTING.md 6Y2: twins s5g1w..s5g3w are sl_rmid2,
s5g4y..s5g6y sl_rturbo_in), or with a console zone around a ring you build (the SmartLanes.zones event, sl_zones.lua
header), then a build touching the ring. Paste back
`make logs-grep PAT='SPLIT|RSPLIT|layout=sl_r(mid2|turbo_in)|VERIFY ring' ARGS='--session live'`.
1. **sl_rmid2, 2-lane ring with 2-lane arms, no mid nodes**: one `SPLIT ring= node= len= edges=<4 ids> nodes_added=4
   zid=`, `WRITE kind=split ring= success=true`, then `RSPLIT ... mids=4 per_stretch=1 nodes=<4 ids> zid=` and 8 `APPLY
   ... layout=sl_rmid2 zid=` (4 junctions `after=5`, 4 mid nodes `exits=0 entries=0 ... before=2 after=4 ... mid=yes`),
   `VERIFY ring= same=8 nodes=8`. `SPLIT ... refused=short` on an XS ring (halves under 8 m): the twin is turbo
   (`RSPLIT ... mids=0 fallback=sl_rturbo`), exclude it. Traffic (visible): cars entering in the curb lane bound for a
   farther exit move in at the mid node; the queue at the inner entry lane (user's ring 282381) shorter than on the
   sl_rturbo twin.
2. **sl_rturbo_in, 4-lane ring with 3-lane arms**: 4 `APPLY ... layout=sl_rturbo_in ... after=10 zid=`, VERIFY same=4.
   Traffic: cars enter the innermost ring lane from the innermost entry lane, circle there and move one lane out at
   the arm before their exit; nobody stops at the shift.
3. The game twin and the sl_rturbo twin: no SPLIT, no mid=yes.

## DS. Default: the mid-node spiral on 2-lane rings with one-lane exits; Smart Lanes adds the mid nodes; the tool on mid nodes (rev 6, PLAN.md "Default: the mid-node spiral", "Smart Lanes adds the mid nodes"; 2026-10-14, the split not run in game yet)
Mods: Smart Lanes and Roundabouts & Interchanges. A free game, a town. Every step: paste `grep -E "SQRL\] (SPLIT|RSPLIT|APPLY|WRITE|VERIFY|ERROR)"`.
1. Place five Better Roundabouts: Ring lanes 2, Arm road Town small, 4 arms, Scale XS, S, M, L, XL. Per ring, expect:
   `SPLIT ring=<key> node=<key> len=<126|159|192|280|439> edges=<4 ids> nodes_added=4`, `WRITE kind=split ring=<key>
   success=true`, then (a job later) `RSPLIT ring=<key> node=<key> len=<same> mids=4 per_stretch=1 nodes=<4 ids>`, 4 junction
   `APPLY ... layout=sl_rmid default=one_lane_exits` (`after=3`: outer lane into the exit only, inner lane straight only,
   entry into the outer lane only) and 4 `... exits=0 entries=0 ... before=2 after=4 ... mid=yes` (both lanes straight
   plus both lane changes), `WRITE ring=<key> ... success=true`, `VERIFY ring=<key> same=8 nodes=8`. No `ERROR`, no crash in the next
   minutes (the split adds nodes with configs; a script node without one can crash the sim, findings roads.md).
   The ring looks as before (the halves are exact sub-curves); the arms' traffic lights (from 1950) go off as usual.
2. Refusals: a ring with a bus stop on a ring piece (Road Stop on the ring), or the smallest possible ring: `SPLIT ...
   refused=edge_objects` / `refused=short`, then `RSPLIT ... mids=0 fallback=sl_rspiral` and `layout=sl_rspiral` APPLYs.
3. Unchanged elsewhere: Town medium arms (2-lane exits): no SPLIT (since 2026-10-15 matched lanes, `layout=matched
   default=two_lane_exits`: step MD; before `turbo=true`, no `layout=`); Ring lanes 4: no SPLIT; a
   Roundabout Interchange ring: as before.
4. Build a road onto one arm of a ring of step 1: `SKIP ... reason=same` for its 8 nodes, no SPLIT, no `reason=hand_edit`.
5. Smart Lanes tool on a ring of step 1 (click between two junctions): the detail line "Apply or Reset: the roundabout and
   its lane changes between the arms"; status "Smart lanes"; short orange curves at each mid node (both straight faint,
   outer into inner and inner into outer bright, crossing); no `ERROR where=mid_lines`. Paste a screenshot.
6. Reset: `RESET` lines for the 4 junctions and the 4 mid nodes (the nodes stay, straight on: Reset never merges them
   back), the curves vanish, status "Game default". Apply again: back to step 1's lanes, no SPLIT (the nodes are there).
7. Apply on an old ring (one placed before this version, 4 ring nodes, Apply automatically Off while placing): `SPLIT
   src=tool ... nodes_added=4`, `WRITE src=tool kind=split ... success=true`, then the tool's `APPLY src=tool layout=turbo`
   lines for 8 nodes (the re-apply 5 frames later).
8. Cars (visible only): entering cars stay in the outer lane to the next exit or move into the inner lane at a mid node.

## MD. Default: matched lanes on 2-lane rings with wide exits (rev 8, PLAN.md "Default: matched lanes on 2-lane rings with wide exits"; 2026-10-15, offline only, not run in game yet)
Mods: Smart Lanes and Roundabouts & Interchanges. A free game, a town. Every step: paste `grep -E "SQRL\] (SPLIT|RSPLIT|APPLY|WRITE|VERIFY|SKIP|ERROR)"`.
1. Place a Better Roundabout: Ring lanes 2, Arm road Town medium (2-lane exits), 4 arms. Expect 4 `APPLY ... lanes=2 ...
   turbo=false fresh=true ... layout=matched default=two_lane_exits` (`after=6`: both ring lanes exit or go on, entries
   lane for lane), `WRITE ... success=true`, `VERIFY same=4 nodes=4`; no `SPLIT`, no `RSPLIT`. Crossing Tool on an arm:
   the outer ring lane goes into the curb exit lane and straight on. Paste a screenshot.
2. Unchanged: a Ring lanes 4 roundabout with Town medium arms: `turbo=true`, no `layout=`; a Ring lanes 2 roundabout with
   Town small arms: `layout=sl_rmid default=one_lane_exits` (step DS); a Roundabout Interchange: its on-ramp keeps its own
   lane (`entry=own_lane`), and with a 2-lane off-ramp the arm junctions are matched (`default=two_lane_exits`).
3. An old save (a 2-lane ring with medium arms written by rev 7 or earlier, turbo): load it, nothing changes on load
   (no `APPLY`). The tool on that ring: status not "Smart lanes", Apply enabled; build a road onto one arm instead:
   4 `APPLY ... layout=matched default=two_lane_exits`, no `SKIP ... reason=hand_edit`.
4. Tool Apply on a ring of step 1 after Reset: `APPLY src=tool layout=turbo ... turbo=false turbo_reason=two_lane_ring`,
   the result line "Smart lanes applied to 4 junctions" with no "no exit-only outer lane" reason; status "Smart lanes".
5. Cars (visible only): at a busy 2-lane ring with 2-lane arms, through traffic uses both ring lanes (the bench s5
   RINGLANE shares: ~50/50), not one queue in the inner entry lane.

## WR. Whole rings in the automatic pass (PLAN.md "Whole rings in the automatic pass"; 2026-10-13, not run in game yet)
1. Place a Better Roundabouts 4-lane ring (medium arms) with Apply automatically Off, save, load with it On, then
   build a road onto one arm. Check: one `APPLY` per arm junction of the ring, all `turbo=true fresh=true`, one `WRITE
   success=true`, `VERIFY same=4 nodes=4`; the Crossing Tool shows the exit-only outer lane at every arm.
   Lights: only the rebuilt arm's junction gets a `LIGHTS` line.
2. Build onto the arms one at a time in a different order on a second such ring: the same lanes at the end.
3. Hand edit: change one junction with the Crossing Tool, then build onto another arm. Check: `SKIP ring= node=<edited>
   reason=hand_edit`, `APPLY` for the rebuilt arm only with `turbo=false fresh=false`, the edit unchanged.
4. Several quick builds on one ring (high game speed, town growth): any `WAIT kind=ring` line is followed by that
   job's `APPLY` / `WRITE` lines; no `ERROR`, no `success=false`.

## BL. Bus lanes: car lanes set, bus connections kept (rev 6, PLAN.md "Bus lanes"; 2026-10-13, not run in game yet)
Player request: "ignore bus lanes but set all the other lanes; I'll add the bus connections / bus priority phases
myself". Use the Bus Lane Tool (Roads, Tools) on town roads; keep the Crossing Tool open next to Smart Lanes.
1. Crossroads with a bus lane on one road (Apply automatically On, then build a road onto it): one `APPLY kind=slip
   ... case=X`, no `SKIP reason=bus_lane`. Crossing Tool: no car lane leads into a bus lane that the game did not
   connect already; the curb car lane (next to the bus lane) turns right; every bus-lane connection the game had is
   still there (compare a `make logs-grep PAT='CONN.*node=<n>'` dump before / after, or the Crossing Tool by eye).
   `VERIFY same=1`.
2. Add a bus connection with the Crossing Tool (the bus lane into a side road), then select the junction with the
   Smart Lanes tool: badge still "Smart lanes", Apply hidden (greyed before 2026-10-14), detail "... bus lanes kept as they are". Press
   Reset: the car lanes go back to the game default, your bus connection stays. Apply again: it stays too.
3. Same junction with traffic lights, Light phases = Game default and Free curb turn Always: open its Crossing
   window: the bus connections have the phases they had before Apply (the bus curb turn is not freed); with Light
   phases = Smart Lanes (`PHASES ... plan=`): every bus connection is green in some phase, none is red all cycle.
   Watch a bus line through it: buses still use the bus lane and are not stuck at red.
4. Roundabout arm with a bus lane (Bus Lane Tool on one arm): the junction is handled (`APPLY ring=` for it, no
   `bus_lane_arm`); the bus lane's connections to the ring stay; with "No lights at roundabouts and ramps" On that
   junction keeps its traffic light (no `LIGHTS` line for it), the other junctions lose theirs.
5. Slip lane leaving a road with a bus lane (Channelized Junction on a bus-lane road): `APPLY kind=slip`, the curb
   car lane feeds the slip lane; the junction keeps its light.
6. A road where a bus lane starts (2 car lanes become 1 car lane + bus lane): `APPLY kind=drop shape=lane_drop...`
   (a drop for cars); the game's connections into the bus lane are kept. Watch: do cars still try to use the bus
   lane? (Open question: does the game connect a car lane into the bus lane there, and do cars ever route over such
   a connection?)
7. A roundabout drawn with a bus-lane road as the ring: every ring junction "not handled: the ring has a bus lane",
   nothing written (`SKIP ... reason=bus_lane_ring` from the tool's pick, no APPLY).
8. One-way street with a contraflow bus lane meeting a two-way road: the crossing rule treats the street as one-way
   for cars; the contraflow bus lane's connections are kept.
9. Unknown offline: whether the engine keeps re-written bus connections byte for byte (VERIFY leaves them out, so
   step 1's comparison is the check). The base Bus Lane Tool makes lanes "exclusive to buses and trucks"
   (`base/content/gui/construction/tools/bus_lane_tool.script.tl:10`): trucks use the kept connections too, and a
   truck route that needs a car lane at the junction gets the car rule's lanes; watch a truck line through step 1.

## RK. Reset sticks (rev 7; PLAN.md "Reset sticks"; implemented 2026-10-14; steps 1-3 passed in game 2026-10-14, 4-5 open)
1. Medium street with a T-junction, Apply automatically On. Tool: Reset the T. Hover: "Game default (locked)";
   log `KEPT op=add n=1 total=1 src=tool`.
2. Place a street bus stop on one arm, then upgrade another arm: the T keeps the game's lanes; log
   `SKIP kind=kept ... reason=reset_kept`, no `APPLY ... node=<T>`.
   **Passed 2026-10-14** (live session of 18:10 UTC, T node 7410): Reset -> `KEPT op=add n=1 total=1 src=tool`; a
   one-lane fourth arm built onto it -> `SKIP kind=kept job=6 ... reason=reset_kept`, the crossroads kept the game's
   21 connections (`badge=kept`); that arm removed and the east arm rebuilt (5145 -> 6719) -> `SKIP ... job=7`, the T
   back to the game's 12 (`badge=kept`); console read `kseq 1 kept 1`. No APPLY on 7410 after the Reset.
3. Apply on the T: smart lanes, status "Smart lanes", `KEPT op=remove`. Rebuild an arm: smart lanes stay.
4. Roundabout: Reset the whole ring, rebuild one arm: the ring keeps the game's lanes (whole ring skipped).
5. Save, reload: step 2 still holds. A save that never used Reset: no `kept` in the state (no KEPT lines).

## OE. Open exit lanes near stops and close junctions (rev 7; PLAN.md "Open exit lanes near stops and close junctions"; implemented 2026-10-14; steps 1-3 passed in game 2026-10-14, 4-6 open)
**Run 2026-10-14** (live session of 19:03 UTC, T node 4538): step 1 `open=-` (8 connections); step 2 stop placed ->
`open=4396:stop`, 9 connections, the left turn `8736:2 -> 4396:3` and `4396:4` (both lanes), the right turn `8880:1 ->
4396:4` only; a fourth arm added: crossroads still `open=4396:stop`; step 3 stop removed -> `open=-`, placed again ->
`open=5921:stop`. Also RK step 3: Reset `KEPT op=add`, Apply `KEPT op=remove`, the next build applied smart lanes.
Apply automatically On, Free curb turn as set, Light phases "Game default". The lane view of the tool shows which exit
lanes a turn reaches.
1. Medium town street (2 lanes each way) with a T-junction, side street at least ~150 m long with no junction on it.
   Log: `APPLY ... node=<T> ... open=-`. Tool, hover the T: the left turn (right in left-hand traffic) from the main
   road into the side street lands in the side street's inner lane only.
2. Place a street bus stop on the side street, curb side, ~25 m after the junction. The stop rebuilds the side
   street's piece, the T goes to the automatic pass: `APPLY ... node=<T> ... open=<side street edge>:stop`. Tool view:
   the left turn into the side street now lands in both lanes; the right turn from the other main approach still only
   in the curb lane; the main road's straights as before. Status "Smart lanes". AUDIT_SUMMARY may show
   `forced=...shared_open:1` (by design, no AUDIT line for it). A bus line turning left there stops without a U-turn.
3. Remove the stop: `APPLY ... open=-`, the left turn back to one lane. (If the stop is placed on a different edge than
   the junction's piece, check the distance: within 80 m of the junction opens, farther does not.)
4. A short block: two T-junctions (or a T and a crossroads) on one street about 50 m apart, side streets to the
   same side. `APPLY ... node=<first junction> ... open=<edge to the second>:near`; the turn across traffic into
   that block lands in both lanes. Junctions 100 m apart: `open=-`.
5. A lit 2x2 crossroads with a stop ~30 m into one arm: `open=<arm>:stop`, the left turn into that arm in both lanes,
   the opposite straight and the right turn unchanged. Unlit (lights off at the node): the left turn stays in the far
   lane on a 2x2 crossroads (the opposite straight already uses both lanes; no crossing), `open=` still logged.
6. If step 2 shows `open=-` although the stop is there: paste in the console, hovering nothing, with `<edge>` the side
   street's piece from the APPLY / PICK line:
   `local e=api.engine.getComponent(<edge>,api.type.ComponentType.BASE_EDGE) for _,o in ipairs(e.objects) do local eo=api.engine.getComponent(o[1],api.type.ComponentType.EDGE_OBJECT) print("SQOE",o[1],o[2],eo and eo.param,eo and eo.transf and eo.transf:getTransl().x,eo and eo.transf and eo.transf:getTransl().y) end print("SQOE enum",api.type.enum.EdgeObjectType.STOP_LEFT,api.type.enum.EdgeObjectType.STOP_RIGHT)`
   and report the `SQOE` lines (`make logs-grep PAT='SQOE' ARGS='--session live'`).

## SH. Rev 8: shared-lane curb turns held, whole lanes and bus lanes in Smart Lanes phases, Lights only, lane status reason (PLAN.md "Rev 8"; 2026-10-14, offline only, not run in game yet)
From a player's report (lit 1-lane crossroads, main road with bus lanes + tram, Light phases = Smart Lanes). The
reasoning behind step 1 (a freed turn out of a shared lane keeps a demand-actuated phase from ending) is inferred, not
seen in game: steps 1-2 check it. Setup: Free curb turn = When safe, then Always; a town with traffic.
1. **Free curb turn, 1-lane crossroads.** Build a lit crossroads of two 1-lane town streets (or Apply on one). Log:
   `APPLY ... node=<n>`, `WRITE`/`SUMMARY ... free_turn=0 free_phases=0 ... shared_held=4`. Crossing window, phases:
   every right turn (left in left-hand traffic) red together with its approach's straight. Watch a few cycles: a phase
   whose approach is empty ends early (the next phase starts before the full green) while the other road waits.
   Compare with rev 7 if a save has an earlier write: Apply again turns `shared_held=4` and re-locks the freed turns.
2. **3-lane crossroads** (curb lane turns only): `free_turn=4 ... shared_held=0`, the curb turns still freed as in FK.
   A 2-lane crossroads with Smart Lanes' lanes: `free_turn=0 shared_held=4` (its curb lane goes straight too).
3. **Light phases = Smart Lanes, 1-lane crossroads, main road with curbside bus lanes** (the player's case: e.g. a
   medium street with bus lanes crossing a small street, bus connections as the game made them). Apply (or Lights
   only): since the axis plan (AX) `PHASES src=tool node=<n> phases=sl pattern=axis plan=x4_axis cycle=60`: one phase per road,
   both directions whole, **the bus lanes green with their road** (Crossing window: the bus lane's straight and turn
   unlocked together with the car lane beside it), a 6 s pedestrian phase after each road. Lengths from lane counts
   only (the main road factor is gone, PHASES_PLAN.md "Whole lanes and bus lanes"): offline 24 s per road (the 2-lane game green 23.7 s as floor; car lane +
   bus lane); a longer green for the busy road comes from Re-time (RT). (Before the axis plan: `plan=x4_split`, four
   approach phases of 18 / 14 s at a 90 s cycle; gone since 2026-10-16, NC.) Watch (player's points):
   cars turning right from the car lane drive while the buses beside them go (no stall behind a stopped bus); a phase
   ends early when its approach (car and bus lane) is empty. If the right-turners still stall beside a green bus lane:
   paste the PHASES line and the Crossing window's phase.
7. **Whole lanes** (Light phases = Smart Lanes; player: "the one car that wants to turn left while everybody else goes
   straight blocks the flow and prevents the phase skip"). On a lit T of 1-lane streets and on a 2-lane crossroads
   (Smart Lanes' far lane goes straight too) Apply / Lights only, then in the Crossing window check every phase: an
   entry lane's movements are all unlocked or all locked (never a straight green while the left turn out of the same
   lane is red). The T: `plan=t3_axis`, the main road's phase greens both main approaches whole. Watch: no phase runs to full length because a
   left-turner holds the lane; phases skip when their lanes are empty.
8. **Bus lane beside a protected axis** (dropped 2026-10-16: classic patterns only, which are gone (NC); with the axis plan
   the bus lane is green with its whole road) (optional, a 3-lane main road with dedicated left lanes and a curbside bus lane
   whose connections also turn left): the bus lane is red in the straight phase (its left turn would cross the
   opposite straight) and gets a phase with its own approach instead; the car curb lane next to it is green in the
   straight phase anyway (a pattern seed). Watch whether those right-turners stall behind the red buses (the player's
   effect): if so, note it for the axis-phase rebuild.
9. **Free curb turn beside a bus lane** (Light phases = Game default, Free curb turn = When safe / Always, a 3-lane road
   with a curbside bus lane, dedicated curb car lane): the curb turn is freed only in phases where the bus lane is
   green (`free_phases=` lower than without a bus lane). Watch that the freed right-turners drive.
4. **Lights only** (a button again since rev 8 v2; the checkbox could not be unchecked in the user's test). On the same
   junction edit a lane with the Crossing Tool (e.g. remove a far turn, or add a second lane's turn). Tool: select the
   junction. The lane status shows Custom (or Game or custom); first row Apply and Reset, second row Lights only and
   Re-time (both rows fit in German / Russian). Press Lights only:
   `PHASES src=tool action=lights_only node=<n> phases=sl pattern=axis plan=..`, `LIGHTS src=tool node=<n> to=sl_phases
   ... action=lights_only plan=..`, no `WRITE` line; result "Light phases set for the current lanes". Crossing Tool:
   your lane edit is still there; the Crossing window's phases match the plan. After ~1 s Lights only grays ("Phases
   already the Smart Lanes plan") and Reset is enabled ("Reset the light phases to the game default"). Press Reset:
   `LIGHTS src=reset node=<n> to=game_phases`, result "Light phases reset to the game default", the Crossing window
   shows the game's six phases again (fractional greens), your lane edit is gone only if Reset also wrote the lanes
   (it does when they differ from the game's: tooltip "Reset lanes and light phases to the game default"). With Light
   phases = Game default: the same. Check `user_modified=` on the LIGHTS line and whether the game keeps the phases
   after a nearby build.
5. **Lane status reason.** Hover / select a lit or unlit crossroads of 1-lane streets with the game's lanes:
   "Lanes: Smart lanes = game default (one car lane per road)"; with a bus-lane main road: "...; bus lanes kept)".
   A 2-lane crossroads with the game's lanes still shows "Game default" (smart lanes differ there). Check the status
   panel wraps the longer label (de / ru) and the hover tooltip stays one readable line.
6. If step 1 shows phases still not ending early: paste the PHASES / LIGHTS lines and the Crossing window's phases
   (which connections are green in the phase that runs long); the next suspect is pedestrians (a crosswalk green in that
   phase keeps it busy) or the all-red phases (fixed, never skip).

## AX. Axis plan: one long green per road (rev 8, PHASES_PLAN.md "Axis plan (default since rev 8)"; 2026-10-14, offline only, not run in game yet)
From the player's report (2026-10-14): Smart Lanes' 4-phase split plan backed traffic up across town; the game's
default and their own plan (head start 12.6 s, main road 23.7 s, pedestrians 6 s, cross road 21.6 s, pedestrians 6 s)
run far better. Setup: Light phases = Smart Lanes, a town with steady traffic, a lit crossroads of 1-car-lane roads
(ideally with curbside bus lanes and a tram, the player's case) and a lit 2-lane crossroads and T.
1. **Plan.** Apply (or Lights only) at the crossroads: `PHASES ... pattern=axis plan=x4_axis cycle=60 1:24s/skip1.5[..]
   2:6s/skip3[w1-w4] 3:24s/skip1.5[..] 4:6s/skip3[w1-w4]` (rev 8 v2: greens at least the game's default for the lanes,
   24 s at 2 lanes; a 1-lane X 19 s). Crossing window: phase 1 = one road, both directions, every lane and turn (bus
   lanes and tram included), crosswalks red; phase 2 = every crosswalk green, every vehicle red, Skip on with min 3 s,
   6 s; phase
   3 the cross road; phase 4 pedestrians again. No all-red phases. The T: `plan=t3_axis` (main road, pedestrians, side
   road, pedestrians).
2. **Turns against the opposite straight.** Watch a few cycles: left turners (right in left-hand traffic) wait in the
   junction for a gap or go before / after the opposite straight; note any box jam (vehicles stuck mid-junction into
   the pedestrian phase) and whether the 6 s pedestrian phase clears the junction before the cross road starts.
3. **Phase skip.** A road whose lanes empty ends its phase early (1.5 s minimum) while the cross road waits; a
   pedestrian phase with nobody on the crosswalks ends after its 3 s clearance (rev 8 v2; before: always 6 s). Watch
   cars left inside the box at the end of a road's green: they must clear in those 3 s (the user's screenshots: they
   "cycle out eventually"). If cars still stand in the box when the cross road starts, note it: the clearance option
   (`opts.pedClearance`) goes up.
4. **Compare a busy junction: game default vs axis vs Re-time** (rev 8 v2; players: "shorter phases than default
   harm busy intersections"). One busy lit crossroads with queues on every arm (the user's node 498446 kind: 1-lane
   roads, 20+ cars queued per arm). (a) Reset in the tool (the game's six phases), wait 5 game minutes, then run
   Re-time once without writing (cancel at the end is not possible: read its `op=measured` q_arm instead, or note the
   queue lengths by eye on each arm). (b) Lights only (the axis plan), 5 game minutes, the queues again. (c) Re-time,
   let it write (`op=plan ... cycle=<old>><new> y= lost= cycle_reason=saturated` expected: cycle 120 s), 5 game
   minutes, the queues again (a second Re-time's `op=measured q_arm=` measures them). Report the three q_arm lines (or
   the queues by eye) and the PHASES / RETIME plan lines. Expect (b) at least as good as (a) (no green shorter than the
   game's) and (c) the shortest queues if the junction is saturated; if (c) is worse (a 120 s cycle spills queues back
   into the next junction), note it: cycleMax goes down.
5. **Stress Test A/B.** Done for lit crossroads: the Light plans A/B (twins game / sl_phases / sl_classic, then sl_auto)
   ran 2026-10-14 (RESULTS.md: axis +23-26 % cars/min vs game, classic worse than game; sl_classic removed 2026-10-16).
   Open: lit T-junctions (no axis-vs-game bench run yet).
6. **Wide roads.** A lit 3x3 crossroads (`x4_axis cycle=68`, 28 s per road): do pedestrians finish crossing a 27 m road
   in the 6 s phase plus the next road's start, or do vehicles drive through them? If they do, raise the pedestrian
   phase (`opts.pedPhase`, no setting yet) and note it.
7. Report: the PHASES lines, Crossing window screenshots of the phases, queue observations game vs axis.

## RT. Re-time: phase lengths from measured traffic (rev 8, PLAN.md "Re-time"; RETIME_PLAN.md step A; 2026-10-14, offline only, not run in game yet)
Answers the step B questions (RETIME_PLAN.md "Open in-game questions"). Setup: a town with steady car traffic and a lit
crossroads where one road is clearly busier (e.g. a medium main street crossing a small street), its phases the game's
default (or anything: Smart Lanes', hand-made). Game speed 1x or 2x; keep the tool open and the junction selected for
the whole run (about 3.5 game minutes). `make logs-grep PAT='RETIME|to=retime' ARGS='--session live'` reads it back.
0. **Rev 8 v2** (cycle from the measurement, background run, status lines, cheaper sampling; RETIME_PLAN.md "Step A
   v2"). You no longer need to keep the junction selected or the tool open; steps 8-11 check that.
1. **Button and status.** Select the junction: Re-time shown in the second row next to Lights only (fits in de / ru;
   the tooltip lines readable). An unlit junction or a street selection: no second row; grayed only while a change of
   the tool lands. Press Re-time: `RETIME op=start node=<n> window_s=180 every_s=3 time=game ...
   kinds=veh/all_red/veh/all_red/walk/all_red durations=..` (the game's six phases); a third status line counts
   "Re-time: measuring traffic (12 of 180 s)" in game seconds (it stops while paused); Re-time's tooltip "Measuring:
   click to cancel", Lights only grayed "Re-time is measuring here".
   Check the game stays smooth (no stutter every 3 s; SQPERF section `retime` with the debug setting On).
2. **Measured.** After 180 game s: `op=measured samples=~60 src=routed cand_max= ... far_skipped= reads= calls=
   calls_per_sample= ... passes=<in>out:n,..> queue=.. q_arm=..`. **Answers:** src=routed (the per-entity lists work at
   junction nodes; src=scan means every call failed); passes per movement plausible against what you see (the busy
   road's straights largest); `lost` small; cost: `calls_per_sample` (expected roughly 40-45 % of the ~8.9k per sample
   the user's first run implies: cand_mean=1425 near_mean=314.6 reads=104429) and `busy_ms` / `frames` (first run:
   7229 ms over 6993 frames). If `passes=-` with visible traffic: paste the line (paths not read, or the node not on
   them).
3. **Plan and write.** `op=plan result=write ... old=<durations> new=<durations> cycle=<old>><new> y= lost= sat=
   sat_src= cycle_reason=` (rev 8 v2: the cycle from the traffic: a busy junction with standing queues goes to 120 s,
   cycle_reason=saturated or queues; a quiet one shortens toward 40 s, cycle_reason=webster|min; the busy road's phase
   longer), then `LIGHTS src=tool node=<n> to=retime ... action=retime`, `op=write sent=1`, status "Phase lengths set
   from the measured traffic". Crossing window: only the green phases' seconds changed; every phase's red / green lanes
   and Skip as before; minimum durations as before. `result=fits` / `small_sample` say why nothing was written.
4. **Probe: the node and the config** (`op=probe at=cb` and `at=f30`): `exists=true config=true same_durations=true
   same_locked=true`. **Answers:** the node id survives a phases-only proposal (exists=false or config=false at f30:
   the node was re-created: step B must key junctions by position); the config reads back with our durations and the
   same lockedLanes (false: the engine re-made or clamped them: paste the lines).
5. **Probe: the running phase** (`op=probe at=before|cb|f30|s5|s30 state= time= state_times=`). **Answers:** whether the
   cycle restarts at phase 0 on a write (state=0 with a small time at cb / f30 while before was another phase) or
   keeps running (state and time continue). A restart on every write costs a partial cycle: step B then writes rarely.
6. **Probe: re-routing** (`op=reroute at=base5|base30|s5|s30 tracked= same= exit_changed= dropped= gone=`).
   **Answers:** do drivers that had the junction ahead change their path because of the write? Compare s5 / s30 with
   base5 / base30 (the same count over the same delays without a write, measured during the window): clearly more
   `exit_changed` + `dropped` after the write than in the baseline = a write triggers re-routing (step B must write
   rarely or not at busy times); about the same = no effect.
7. **user_modified** on `op=start`, `op=probe at=before` and `at=f30` (and the LIGHTS line): whether a script write
   sets `userModifiedTrafficLightStates`.
8. **Cancel and abort.** Start Re-time and press it again: `op=cancel reason=button`, status "Re-time: canceled".
   Start, then edit a phase in the Crossing window: within 3 game s `reason=changed:phases`, "Re-time: the junction
   changed, stopped". Start, then select another lit junction: no cancel; its Re-time is enabled (rev 9: up to 5
   at once, "RT5") and the status says "Re-time measuring junctions: 1"; back at the first junction the progress line
   shows.
9. **Background run** (rev 8 v2). Start Re-time and close the tool (or switch to another tool) right away. Wait
   ~3.5 game minutes. **Answers:** `RETIME op=bg node=<n> phase=measuring` (the background plugin stepped it: it shares
   the tool's Lua state), then `op=measured ... gaps=0`, `op=plan`, `op=write sent=1` and the probe lines with the tool
   closed. If no `op=bg` line and nothing until the tool is reopened: the plugin runs in another Lua state (note it in
   docs/findings/gui.md); reopening the tool then resumes the run and `op=measured` shows `gaps=1 gap_s=<closed time>`.
10. **Last result.** Reopen the tool and select the junction: two status lines "Measured 2 min ago: 18 / 7 cars/min per
   road" and "Cycle 71 -> 120 s, greens 23.7/23.7 -> 48/48 s" (or "Already fits the traffic (cycle 71 s)" / "Too little
   traffic measured, phases kept"); select another junction and back: still there; reload the game: gone.
11. **Reset undoes it.** After a Re-time write, Reset is enabled ("Reset the light phases to the game default"); press
   it: `LIGHTS src=reset to=game_phases`, the Crossing window's six phases with fractional greens again, Reset grayed.
12. Report: the RETIME lines of one full run (start to s30), the Crossing window's phases before / after, and whether
   the busy direction's queue got shorter over the next few minutes (with AX step 4's comparison).

## RT5. Several Re-time runs at once (rev 9, PLAN.md "Several Re-time runs at once"; 2026-10-17, offline only, not run in game yet)
Read back with `make logs-grep PAT='RETIME op=' ARGS='--session live'`. Setup: a town with steady car traffic and at
least 6 lit crossroads; the debug setting On for the SQPERF `retime` section; one junction enrolled in Keep timing
adjusted (for step 5).
1. **Two at once.** Re-time at junction A, then at junction B: `op=start node=<B> ... running=2`. Each junction's status
   shows its own "Re-time: measuring traffic (<s> of 180 s)"; a third junction and nothing selected show "Re-time
   measuring junctions: 2". After 180 game s each: its own `op=measured`, `op=plan`, `op=write sent=1` and "Phase
   lengths set from the measured traffic" (the Crossing window: each junction its own new greens).
2. **Five, and the sixth.** Start Re-time at 5 junctions (`running=5`). At the 6th lit junction the button is grayed,
   its status ends with "Grayed out: Re-time is measuring 5 junctions, the most at once"; a click gives the same text
   and `op=refuse reason=full running=5`. **Answers:** the game stays smooth at 1x and 4x (no stutter every 3 s;
   SQPERF `retime` at most ~1.5 ms a frame, as with one run); `op=measured samples=` lower than ~60 only when the
   junctions are busy (a sample then takes more frames); `window_s=` ~180 each.
3. **Cancel one.** At one of the five press Re-time: `op=cancel reason=button ... running=5`, status "Re-time: canceled";
   the others' progress keeps counting and each writes at its own end. The 6th junction's Re-time is enabled again.
4. **Ending together.** Start two within a few seconds of each other: both `op=measured` close together, the second
   `op=write` after the first landed (its status "Re-time: waiting for the last change to land" for a moment), both
   `sent=1`.
5. **Keep timing adjusted pause.** While any run measures, the enrolled junction takes no `AUTORETIME op=snapshot`;
   within ~2 game min after the last run is written or canceled (also with the tool closed, step 6) they come again.
6. **Tool closed.** Start three, close the tool: `op=bg ... running=3` once per run, each writes with the tool closed.
   After the last write and ~30 game s of probe lines: no RETIME line any more, SQPERF `retime` gone from the frames.
7. **Save and load** with runs measuring: after the load none runs (no progress line, no count line), each junction
   shows its last measured line from before.
8. Report: the RETIME lines of steps 2-4 and whether the game stuttered.

## KA v4. Keep timing adjusted: queue snapshots (rev 8 step B v4; PLAN.md "Keep timing adjusted", RETIME_PLAN.md "Step B v4"; 2026-10-15, offline only, not run in game yet)
Replaces KA / KA v3 (the 180 s windows; moved to HISTORY.md, never run in that form beyond Light plans A/B run 2).
Setup: a town with steady car traffic and a lit crossroads with one clearly busier road (queues on it). Game speed
1x-4x. Read back with `make logs-grep PAT='AUTORETIME|action=auto' ARGS='--session live'` (and SQPERF with "Debug:
performance log" On: section `auto`, ctx `bg`). Steps 1-5 at one junction, 6-8 the runtime's conditions, 9 the whole
map.
1. **The toggle** (twin Yes / No params since 2026-10-15). Select the lit crossroads: a third row under Lights only |
   Re-time, "Keep timing adjusted [Yes|No]" with No selected (fits in de / ru on its own row, a separator line above
   it as between the other rows; label and toggle not clipped). An unlit junction, a roundabout, a street: no third
   row. Click Yes: `AUTORETIME op=enroll node=<n> pos=<x,y> src=tool total=1`, result "Timing kept adjusted at this
   junction", Yes selected, then the status "Keep timing adjusted: counting waiting cars (0 of 8)" (counting up
   every 2 game min). The tooltip reads in 9 lines, none too wide. Clicking the side already selected does nothing.
2. **Right before the first click, and per junction.** Reload the save (a fresh menu), open the tool and select the
   enrolled junction **before clicking anything**: Yes selected (the twin with default Yes). Select an unenrolled lit
   junction: No. Click Yes at one junction, then select an unenrolled one: No (not the Yes you clicked elsewhere); back
   at the first: Yes. Click No: `op=unenroll ... src=tool total=0`, "Timing no longer adjusted at this junction", No
   selected; select elsewhere and back: No. Click Yes again for the next steps. **Report** whether the toggle ever
   showed the wrong side (before or after the first click), and whether the row flickered when switching twins.
3. **Snapshots, tool closed.** Close the tool right after clicking Yes. Every 2 game min: `op=snapshot n=1 src=routed
   cand= read= drivers= near= counted= calls= frames= busy_ms= max_frame_ms= fetch_ms= finish_ms=`. **Answers:** the background plugin runs
   the runtime with the tool closed (or never opened: load a save with an enrolled junction, tool not opened:
   `op=snapshot` within ~2 game min); `counted=` about the cars you see standing on the approaches (compare with the
   Stress Test's `q_arm` if a traffic log runs); `max_frame_ms` <= ~1.1.
4. **The first decision and the record.** ~16 game min after enrolling: `op=plan ... result=write|fits|quiet snaps=8
   queued= queue=<seg:mean> arrive= ... cycle=<old>><new> ...`; the busier road's approaches show the larger `queue=`.
   For a write: `op=write ... sent=1 ... every=600`, `op=write ... at=cb success=true`, `LIGHTS src=auto node=<n>
   to=retime ... action=auto`, the busier road's green longer, the cycle moved by at most 20 s. Open the tool, select
   the junction: "Keep timing adjusted: next check in 10 min" and "Last measured 1 min ago (auto): cycle 71 -> 77 s" (or
   "...: already fits" / "...: too little traffic"). Leave it ~60 game min: decisions 10 min apart while it writes,
   then `result=fits` with `every=` 600 -> 1200. **Reload the save**: the box and the "Last measured" line survive (the
   record is saved); the status counts snapshots again from 0 (the averages are not saved).
5. **Manual Re-time there.** Press Re-time at the enrolled junction: the manual measurement starts (`RETIME op=start`,
   "Re-time: measuring traffic (12 of 180 s)"), no `op=snapshot` while it measures; after it, "Last measured just now
   (manual): ..." replaces the auto line, and the automatic mode adopts a manual write at its next refresh (`op=adopt
   reason=durations`, no automatic write there for 10 game min).
6. **Hand edit adopted.** Change a green's seconds in the Crossing window (or press Lights only). Within ~5 game min:
   `op=adopt reason=durations|phases old= new=`; the following automatic write keeps your phases' lanes and skips
   (Crossing window), only lengths differ.
7. **Building nearby.** Keep the road builder open with the cursor next to the junction (within 300 m) when a write is
   due: `op=hold reason=building`, the write after you close the menu (or `op=skip reason=stale held=building` after 2
   game min). **Answers:** the base `constructionMenuActive` event reaches the plugin (no hold ever: it doesn't; note it
   in docs/findings/gui.md).
8. **Re-attach / prune.** Rebuild the junction (bulldoze one arm and build it again, or upgrade a road through it):
   within ~5 game min `op=reattach old=<id> new=<id>` when the node id changed (else nothing), `op=reset reason=lanes`
   when its lanes changed, or `op=prune reason=no_light|gone` when no lit node stands there any more (and `op=unenroll
   ... src=prune`).
9. **Whole map: every lit junction** (the Stress Test's switch, or the console):
   `api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.auto", { op = "all", run = "ka9" }))`
   Expected: `AUTORETIME op=enroll_all phase=request run=ka9 src=stress`, within a few frames `op=enroll_all phase=done
   run=ka9 src=component nodes=<lit> lit= already= sent= capped=` (`src=octree` means the light component could not be
   listed: note it in docs/findings/roads.md) and one `op=enroll ... src=all` per junction (up to 1000). Then
   `op=snapshot n=<watched> src=scan` every 2 game min. Let it run >= 60 game min at 1x and 4x. **Answers:** the
   snapshot cost (`busy_ms`, `frames`, `max_frame_ms`; the person-list frame: SQPERF `auto` max), no stutter, `span_s`
   well under 120, the writes spread (at most one per 5 game s), and traffic before / after (`make flow ARGS='--last'`).
   Stop it: `... { op = "clear", run = "ka9" }` -> `op=unenroll all=1 n=<count> run=ka9`.
10. **Stress Test twins** (Light plans A/B, sl_auto twins, >= 90 game min at 4x): the first `op=write sent=1 ... zid=`
   ~16 game min after the build, balanced twins stop at <= 75 s, no flip-flop; compare after the last write (`make flow
   LOG=<session>`).
11. Report: the AUTORETIME lines of one junction over ~60 min, the SQPERF `auto` line, and for step 9 the
   `enroll_all` lines and a few `snapshot` lines.
12. **Check interval setting** (`sqrl_auto_every`, added 2026-10-15). In the mod settings (new game or Load with mod
   settings) the param "Keep timing adjusted: check interval" shows x0.5 / x1 / x2 / x4 (x1 selected; de / ru / fr
   show "x0,5"); its tooltip reads in 5 lines, none too wide. Set **x2**, load: `AUTORETIME op=config every_factor=2
   params=read` once at the start (`params=unread` or `every_factor=1`: the plugin's state cannot read mod params:
   note it in docs/findings/scripting.md). Enroll a junction (step 1): after its first decision the status says "next
   check in 20 min" (a write or the first fits / quiet; at most 20), `op=write ... every=1200` / `op=plan ... every=`
   doubling 1200 -> 2400 -> 4800 -> 7200 (cap 120 min). With **x0.5**: "next check in 5 min" after a write, cap 30 min.
   Snapshots stay every 2 game min with either.
13. **Early wake** (added 2026-10-15). A lit junction with almost no traffic: enroll it, wait for `op=plan
   result=quiet` (status "next check in 10 min", later 20, 40). Then send traffic through it (a bus line or a new
   road toward a town): within a few snapshots (2 game min each; the average needs ~1.5 standing cars) `AUTORETIME
   op=wake node=<n> reason=quiet_rise queued=0.4>1.5 ... due_was_s=<s> due_s=0`, and the next `op=plan` follows at
   the next look (the status shows "next check in 0 min" until then). Only one `op=wake` per decision. At a junction
   that last said `result=fits` with a real queue (3+ cars standing on average), closing one approach's road (or a
   large new flow on one road) gives `reason=fits_shift` (`shift_cars=` >= 1.5) or `fits_grow` (+1.5 cars to 3+).
   **Since the wake minimums (2026-10-15, after city run 2's 51 wakes vs 21 writes, RETIME_PLAN.md "Wake minimums"):**
   a fits junction with 1-2 cars standing never wakes, however its shares move. Right after a write, a wake waits for
   the write gap (`due_s=` up to 600 at x1). **Report** the wake lines and whether any junction woke too often (more than
   once per ~20 game min while traffic is steady). At scale (step 9 or the city bench): `op=wake` count vs `op=plan
   result=write`; pass: the woken decisions mostly write (run 2 before the minimums: 6 of 51), fits wakes rare.
14. **Snapshot frame cost, wall clock** (added 2026-10-15 after city run 2's `max_frame_ms=81.52` / `49.20`, which were
   `os.clock` readings: RETIME_PLAN.md "Wall clock, not os.clock"). With many enrolled junctions (step 9, > 12, so
   `src=scan`) and "Debug: performance log" On: `AUTORETIME op=config ... clock=wall` at the start (`clock=os`: no
   `api.type.Clock` in the plugin's state; note it in docs/findings/gui.md). Each `op=snapshot ... max_frame_ms=
   fetch_ms= finish_ms=`: expected `fetch_ms` ~1-2 at ~12k persons (~4 at 43k), `max_frame_ms` <= max(fetch_ms, ~1.1),
   `finish_ms` < 1; `frames=` fewer than before (the budget now really 1 ms). Compare with SQPERF `ctx=bg ... auto ...
   max=` of the same window: a window max well above every snapshot's `max_frame_ms` comes from a heavy step or write,
   not the snapshot. **Report** the snapshot lines and the SQPERF lines. If `fetch_ms` is the worst frame and above
   ~5 ms, time the candidate calls in the console (camera over a busy town; reads only, changes nothing; output in the
   log: `make logs-grep PAT='SQTIME' ARGS='--session live'`):
   `local C, CT = api.type.Clock.new(), api.type.ComponentType; local c = api.gui.camera.getCameraData(); local v = api.type.Vec2f.new(c.x, c.y); local out = {}; for i = 1, 5 do local w0, o0 = C:getTime(), os.clock(); local l = api.engine.getEntitiesWithComponent(CT.SIM_PERSON); out[#out + 1] = string.format("list n=%d wall_us=%d os_us=%d", #l, C:getTime() - w0, math.floor((os.clock() - o0) * 1e6)) end; for _, k in ipairs({ "SIM_PERSON", "MOVE_PATH" }) do local w0 = C:getTime(); local ok, r = pcall(api.engine.util.octree.findEntitiesInCircle, v, 160, CT[k]); out[#out + 1] = string.format("octree %s ok=%s n=%s wall_us=%d", k, tostring(ok), ok and tostring(#r) or tostring(r), C:getTime() - w0) end; print("SQTIME " .. table.concat(out, " | "))`
   It prints the full list's wall and `os.clock` time five times and whether the octree returns persons in a 160 m
   circle (`ok=false` or `n=0`: no per-area person query; a failing call may log a traceback). Record the answer in
   docs/findings/lines-vehicles.md.

## AL. All lights + first-load welcome (PLAN.md "Automatic timing for all lights + first-load welcome"; 2026-10-15, offline only, not run in game yet)
Read back with `make logs-grep PAT='WELCOME|MAPPASS|op=(enroll_all|cap_hit|mode|optout|optin|config|new_lights|enroll_new)' ARGS='--session live'`
(and `make logs-grep PAT='job=m[0-9]' ARGS='--session live'` for the pass's own APPLY / SKIP / SUMMARY lines).
1. **Welcome, new game** (not the map editor): ~3 s after the game is up a "Smart Lanes" window: three short lines,
   "For what is already on this map:", two checkboxes ("Convert all existing junctions to Smart Lanes" ticked,
   "Switch all traffic lights to automatic timing" unticked; texts 2026-10-16), the info card "Save your game first ...", [Apply]
   [Not now]. Log `[SQRL] WELCOME op=show`. Check in en and de / ru: nothing clipped, the window not wider than
   needed, tooltips on both boxes and buttons in short lines. Where does it open (default position)?
2. **Not now** (or the window's X): `WELCOME op=answer answer=later lanes=0 lights=0 mode=- pass=-`. Save, load: no
   window, no WELCOME line. A second load of a save that never answered (quit without answering): the window again.
3. **Apply on an existing city** (save first; tick the lights box too): `WELCOME op=answer answer=apply lanes=1 lights=1 mode=all pass=1`
   (lights box left unticked: `lights=0 mode=-`, the setting's mode stays), then
   `MAPPASS op=start seq=1 src=config list=<n> resume=0` (src=node / octree / none = the component list failed),
   `op=progress` every 10 slices, `op=end seq=1 reason=done slices= junctions= scanned= list= frames=`. Watch the
   frame rate while it runs (slices of 160 junctions; SQPERF `job_step` with the debug setting). The tool, nothing
   selected, shows "Setting smart lanes at all junctions..." until the end. Spot-check: roundabouts, slips,
   crossroads got smart lanes (lane status "Smart lanes"); a junction edited with the Crossing Tool before kept its
   lanes (`SKIP ... reason=hand_edit`); a junction you Reset kept the game's (`reason=reset_kept`); no traffic light
   switched on or off. A second load: no new MAPPASS start.
4. **All lights listing**: within a few frames of the mode turning all `AUTORETIME op=enroll_all phase=done
   run=allmode src=component nodes= lit= already= optout= hand= sent= capped=`, one `op=enroll ... src=all` per
   junction. Note `hand=`: on a city where Smart Lanes wrote phases before (Lights only, Light phases Smart Lanes,
   Re-time) it should stay near 0 (findings roads.md: our writes set the flag; the whole-second rule must tell them
   apart). A city with more than 1000 lit junctions: `op=cap_hit src=allmode max=1000` once.
5. **Lights built later**: build a lit crossroads; enrolled at once now (step 12); the listing's `op=enroll node=<new>
   ... src=all` within 5 game min only if the build path missed it.
6. **Opt-out**: select an enrolled junction, Keep timing adjusted No: `op=unenroll ... src=tool`, then `op=optout
   node= ... optouts=1`. 5+ game min later it is still No (the next enroll_all line, if any, counts `optout=1`).
   Yes again: `op=enroll ... src=tool`, `op=optin`.
7. **Timed by hand**: in a save with Junctions I choose, set a crossroads' phases in its Crossing window (whole
   seconds), then the settings panel's Automatic light timing All lights (was: the tool's Adjust all lights): that
   junction is not enrolled (`hand=1`); Yes there enrolls it.
8. **The switch in the tool** (nothing selected; rows 4 / 5 replaced 2026-10-15 by the settings panel, "SP"):
   Automatic light timing Junctions I choose: `AUTORETIME op=mode mode=pick src=tool unenrolled=<n>`, status
   "Light timing: junctions you choose (0)"; All lights: `op=mode mode=all ... optouts_cleared=`, the listing follows.
9. **Setting All lights** without the welcome's lights box (Not now in a new game): `op=config ... lights=all` and the
   listing runs anyway.
10. **Map editor**: no window, no WELCOME / MAPPASS line.
11. **Resume**: quit during a long pass (step 3 on a big map), load: `MAPPASS op=start seq=1 ... resume=1`.
12. **New lights at once, a build** (PLAN.md "New lights at once"; All lights, "Apply automatically to new roads"
    Off too): build a crossroads by hand where the game adds lights (1950+, big enough roads), then select it in the
    Smart Lanes tool at once: Keep timing adjusted Yes. Log: `AUTORETIME op=new_lights phase=queued src=build nodes=
    segs=<n> cfgs=<n>`, then `op=enroll node=<new> pos= src=build` (or, when you select it first, `src=select`) and
    `op=enroll_new src=build checked= sent=1 ...`. If the game adds the light a few seconds after the build: `wait=1`
    in the first enroll_new line, the enroll within ~30 game s. Read back with `make logs-grep
    PAT='op=(new_lights|enroll_new|enroll) ' ARGS='--session live'`.
13. **New lights at once, the Crossing Tool**: at an unlit junction pick a light type in its Crossing window (the light
    switched on), then select it in the Smart Lanes tool at once: Yes. Note the log: an `op=new_lights ... segs=0
    cfgs=<n>` line means the light toggle's build event lists the node (findings roads.md "The Crossing window's
    light buttons are a player build": record which, cfgs= and whether `op=enroll ... src=build` came before the
    selection); no new_lights line means it lists nothing and only the selection (`src=select`) enrolled it. Write
    the answer into findings roads.md.
14. **Selection shows why not**: at an opted-out junction (step 6) the status line under the toggle reads "Not
    adjusted: you turned it off"; at a junction timed by hand (step 7) "Not adjusted: timed by hand"; both stay No
    (no `src=select` line). In de / ru / ja: the line fits.

## SP. In-game settings panel: the Smart Lanes tool and the Crossing Tool (PLAN.md "In-game settings panel"; 2026-10-15, offline only, not run in game yet)
Read back with `make logs-grep PAT='SETTINGS|MODE |op=(config|mode)' ARGS='--session live'`. Run 1-3 first: they
decide whether the approach works at all.
1. **Crossing Tool shows the panel** (Roads -> Tools -> Crossing Tool, nothing else changed): on the left, after the
   Road / Tram lanes buttons (and Better Bus Overlay's "Line routes" when it is on), one separator, then five labelled
   settings stacked, then Underground. Log `[SQRL] SETTINGS op=menu where=crossing_tool result=inserted` once (and
   `result=present` at a later menu open). The tool itself still works: click a junction, change a lane, Road / Tram
   mode and Underground toggle as before. If nothing shows: with "Debug: performance log" On the load has
   `SETTINGS op=patch result=installed|already|missing`.
2. **A change in the Crossing Tool**: Light phases -> Smart Lanes: `SETTINGS op=click key=phases value=2 src=crossing
   sent=1`, then `SETTINGS op=set key=phases value=2 param=sqrl_light_phases src=crossing seq=1` and `MODE
   phases=sl free_turn=... lights=... src=save` (the build pass). The ComboBox shows Smart Lanes at once and keeps it.
   Build a lit crossroads: its `PHASES ... plan=` line (Smart Lanes phases) though the mod setting says Game default.
3. **Shown value before any click** (the defaultIndex path): save, quit to the menu, load: open the Crossing Tool:
   Light phases shows Smart Lanes (the save), not the mod setting. Then open the Smart Lanes tool, nothing selected:
   the same values. A new game: the mod settings' values.
4. **Smart Lanes tool**: nothing selected: the panel above the info block (status "Light timing: ..."), no "Adjust
   all lights" / "Stop for all lights" rows any more. Select a junction: the panel goes, the junction's rows show;
   right-click: back. Change Free curb turn -> Off here (`src=tool`); open the Crossing Tool: Off there too (one stored
   value). Apply on a lit crossroads: no curb turn freed (`free_turn=off` in its lines).
5. **Automatic light timing** in either tool: All lights: `AUTORETIME op=mode mode=all src=crossing|tool`, the listing
   follows (AL step 4); Junctions I choose: `op=mode mode=pick ... unenrolled=<n>` (every junction stops: the tooltip
   says so). The welcome's Apply with the lights box shows All lights in the panel afterwards.
6. **Check interval** x4: `AUTORETIME op=config every_factor=4 ... src=save` within a second (the runtime), the next
   decisions' `next=` 4 times longer.
7. **No lights at roundabouts and ramps** Off: build a roundabout: the game's lights stay (no `LIGHTS ... to=off`).
8. **Layout**: en, de, ru: labels above their controls not clipped (the bar is 314 px), ComboBoxes readable, On / Off
   buttons with "Désactivé" (fr) whole; every control's tooltip in short lines with "Set here, it applies to this game
   only ...". Gamepad mode (if available): the panel still usable.
9. **Persistence**: save, load: the values kept (no SETTINGS line at load, one `MODE ... ` with the save's values).
   Another save / a new game: the mod values.
10. **Removing the mod** (RM): `sset` / `sseq` go with the game script.

## TR. Record traffic (PLAN.md "Traffic rate at a junction"; 2026-10-16, offline only, not run in game yet)
Read back with `make logs-grep PAT='TRAFFIC op=' ARGS='--session live'`. Setup: a town with steady car traffic, a
crossroads and a roundabout. Steps 1-3 first: they decide whether the counts are right and cheap.
1. **Button and live text.** Select a junction (lit or not): a last row "Record traffic" above the info block (de / ru:
   not clipped; tooltip lines readable). Nothing selected or a street: no such row. Press it: `TRAFFIC op=start
   kind=node node=<n> ... every_s=5 window_s=1200 bucket_s=30 time=game`; the status shows "Recording traffic: 0 of 20
   min", after 30 game s also "Vehicles per minute: <r> (<m> min)", from 3.5 min "(last 3 min), <r> (all <m> min)". The
   button's tooltip "Recording here: click to stop". The game stays smooth (no stutter every 5 s; with the debug setting
   On the SQPERF section `record`).
2. **Counts plausible.** Watch the junction for one game minute and count the cars crossing it by eye (or compare with
   the Stress Test's flow at a Showcase junction): the rate should match within ~10 %. Press the button again:
   `op=done reason=button ... vehicles= rate_all= rate_recent= saved=1 ... calls_per_sample= ms_per_sample= arm=`; the
   status "Traffic recording stopped", then "Traffic recorded just now (<m> min)" and its rates. Note
   `ms_per_sample` and `calls_per_sample` (first in-game run, `2026-10-16_1815`: 16-18 ms of os.clock, 126-405 calls per sample).
3. **Roundabout.** Select a roundabout between its junctions, Record traffic: `op=start kind=ring node=<ring key>
   nodes=<its junctions> cand_ents=<its arm segments>`; the text says "Vehicles entering per minute"; stop after a few
   minutes: `arm=` lists only arm segments, and their sum is about the cars entering (by eye). Select one of its
   junctions: no record of its own (a separate one when recorded there).
4. **Goes on.** (Since 2026-10-16 Record traffic is hidden at a node with fewer than 3 roads: a bend, dead end or lane
   drop; check it once.) Start at a junction, select another junction: its Record traffic is enabled (several at once
   since 2026-10-16, "TM") and the status says "Traffic recordings running: 1"; close the tool and play 2-3 game minutes: `TRAFFIC op=bg` once; reopen and select the junction: the
   minutes went on. A checkpoint every 5 game min (`op=checkpoint ... saved=1`); after 20 game minutes `op=done
   reason=max elapsed_s=1200 saved=1`, the status "Traffic recording finished".
5. **Saved.** Save, load: select the junction: "Traffic recorded <n> min ago (<m> min)" with its rates. A recording
   running at the save is gone after the load (its last checkpoint kept).
6. **Beside Re-time.** At a lit junction press Re-time, then Record traffic: both lines in the status (Re-time's first),
   both run to their ends; Re-time still writes (`RETIME op=write`).
7. **Short and gone.** Start and stop within 30 s: "too short to save (under 30 s)", `saved=0`. Start, bulldoze the
   junction: `op=done reason=gone`.
8. **Previous recording (2026-10-16).** At the junction of step 2 (one saved result) press Record traffic again: under
   "Recording traffic: 0 of 20 min" a line "Previous recording: <r> vehicles per minute (<m> min, <n> min ago)" with
   step 2's whole-recording rate, in a **dimmer grey** than the lines above (note whether it is grey or the same as
   the others: the inline colour against the disabled button's text rule). Stop after a few minutes: "Traffic recorded
   just now", its rates, and the same previous line below. Record a third time: the previous line now shows the second
   result. A roundabout: "vehicles entering per minute". Save, load: the previous line is still there.

## TM. Several traffic recordings at once (PLAN.md "Several recordings at once"; 2026-10-16, offline only, not run in game yet)
Read back with `make logs-grep PAT='TRAFFIC op=' ARGS='--session live'`. Setup: a town with steady traffic, several
junctions and a roundabout; the debug setting On for the SQPERF `record` section.
1. **Two at once.** Start a recording at junction A, then at junction B: `op=start ... running=2`. Each junction's status
   shows its own "Recording traffic: <m> of 20 min" and rates; a third junction and nothing selected show "Traffic
   recordings running: 2". Each gets its own `op=checkpoint` at 5 min of its own.
2. **Stop one.** At A press the button: `op=done node=<A> reason=button ... running=2`; B goes on (its minutes keep
   counting), A shows its saved result and "Traffic recordings running: 1".
3. **Many.** Start recordings at 20 junctions (a busy town; a roundabout among them). The game stays smooth at 1x and
   4x (no stutter every 5 s; SQPERF `record` at most ~1 ms a frame). At the 21st junction the button is grayed with
   "20 recordings running, the most at once"; a click gives the same text and `op=refuse reason=full running=20`.
4. **The stretch.** Let them run 20 minutes (or stop them): note `every_max_s=`, `late=`, `ms_per_sample=` and
   `samples=` of the `op=done` lines at 1x and at 4x (estimate PLAN.md: ~5.5-6 s at 1x 60 fps, ~22-24 s at 4x for 20
   busy junctions). Compare one junction's rate with the same junction recorded alone (step 2 of TR): within ~10 % at
   1x; at 4x note how much lower.
5. **Save and load** with several running: after the load none runs ("Traffic recordings running" gone), each
   junction shows its last checkpoint ("Traffic recorded <n> min ago").
6. Report: the `op=done` lines of steps 3-4 and whether the game stuttered.

5. (2026-10-17, the gathering budget) 15+ recordings at once, performance log On, 10 min at 4x: in `make perf`, the
   tool's `record` section max stays near `record_gather` + ~1.5 ms, no `slow=record` line; before, 17 recordings gave
   ~12.5 ms frames.

## SO. Smart lights stays on after its timing changed (PLAN.md "Smart lights stays on after its timing changed"; 2026-10-16, offline only, not run in game yet)
Read back with `make logs-grep PAT='PHASES|RETIME op=write|AUTORETIME op=write' ARGS='--session live'`. Setup: a lit
2-lane T-junction or crossroads with traffic.
1. **Re-time.** Smart lights, then Re-time (or Keep timing adjusted Yes until `AUTORETIME op=write`): the green times
   change. Select the junction: Smart lights is **hidden** (since 2026-10-16; grayed before), the badge "√ Smart lanes |
   √ Smart lights" (or "Game default | √ Smart lights" on game lanes), the detail line "Smart lights: timing
   adjusted"; Re-time, Keep timing adjusted and Reset still shown.
2. **Crossing window (revised 2026-10-16: a hand edit is no longer "timing adjusted").** After step 1, change a
   phase's duration with its slider. Select the junction: Smart lights is **enabled** again, the detail line "Smart
   lights: timing changed by hand", Reset shown ("Reset the light phases to the game default"). Click Smart lights:
   `PHASES src=tool action=lights_only node=<n> phases=sl hand=1 pattern=axis plan=`, the Crossing window shows the
   plan's greens again (24 / 6 / 24 / 6 s at a 2x2 crossroads), Smart lights grayed "Phases already the Smart Lanes
   plan". Or click Reset instead: the game's phases. Also: Smart lights alone (no Re-time), then a slider change:
   the same (offered again). Change a phase's lanes (lock another lane) instead: Smart lights is offered again, no
   "changed by hand" line.
   - **Keep timing adjusted there:** with the junction enrolled, after a slider change the runtime logs `AUTORETIME
     op=adopt node=<n> reason=durations` at its next look and keeps the hand timing as its base; its next write
     (about 10 game min later, `AUTORETIME op=write ... sent=1`) hides Smart lights again ("timing adjusted"; the badge checks it)
     again. A "fits" decision in between (`op=plan ... result=fits`) leaves it "changed by hand".
   - **Save and load** after step 1 (no hand edit): still hidden, "timing adjusted" (the record's signature is saved).
     A save from a build before this change: the cycle decides (a hand edit that keeps the cycle reads as ours).
3. **A build nearby.** With Apply automatically On build a road near the re-timed junction (its lanes stay): no
   `PHASES src=auto` / `LIGHTS src=auto ... to=sl_phases` line for that node, the Crossing window keeps the fitted
   greens. Change the junction's lanes (add a lane to an arm): its plan is written again (`PHASES src=auto`).
4. **Reset** after step 1: the game's phases back, Smart lights enabled again, "| √ Smart lights" gone from the badge.
5. **Badge checks (user 2026-10-16).** A lit 2x2 crossroads with the game's lanes and phases: the badge "Game default",
   Smart lights enabled. Smart lights: the button hides, the badge "Game default | √ Smart lights". Smart lanes: "√
   Smart lanes | √ Smart lights" in green, one colour for the whole line. Check the mark: it should be a check-like
   `√` (passed in game 2026-10-16: "√ Smart lanes | √ Smart lights" renders, English). A 1-lane crossroads: "√ Smart
   lanes = game default (one car lane per road) | √ Smart lights" wraps in the info block, nothing cut off; de / ru
   too. A roundabout, a slip node: "√ Smart lanes" without "| ..." (no Smart lights there). Hover a junction: the
   cursor tooltip's "Lanes: ..." line shows the same.

## NS. New lights get Smart lights (PLAN.md "New lights get Smart lights"; 2026-10-16, offline only, not run in game yet)
Read back with `make logs-grep PAT='new_light|op=new_lights|plan_new' ARGS='--session live'`. Setup: Apply automatically
On, Light phases = Smart Lanes (mod option or the panel), Automatic light timing = Junctions I choose first; an unlit
crossroads of two-way roads.
1. **Light switched on.** Switch the crossroads' light on in the Crossing Tool: `AUTORETIME op=new_lights ... segs=0
   cfgs=<n> plan=1`, then within a second `LIGHTS src=new_light node=<n> to=sl_phases ... action=new_light plan=` and
   `PHASES src=new_light node=<n> phases=sl pattern=axis plan=`; the Crossing window shows 4 phases (two greens, two
   6 s pedestrian phases), the Smart Lanes tool's Smart lights button there is hidden, the badge ends "| √ Smart lights". No second
   LIGHTS line for that node from the write's own build event.
2. **Left alone.** Change a green in the Crossing window (timed by hand), then switch the light off and on: no new
   `src=new_light` line while the phases are not the game's (note whether switching off and on gives the game's
   default phases again; if it does, the plan is written, as for a new light). Reset a junction with the tool (kept),
   switch its light off and on: no `src=new_light` line.
3. **A T-junction** with a light switched on: the axis plan too (`pattern=axis`). A 5-arm junction: `plan_fail=` and the
   game's phases stay.
4. **Game default** (panel): switch a light on: `plan=0` or no `op=new_lights` line, no `src=new_light`. Apply
   automatically Off with Smart Lanes phases: no plan (by design).
5. **With all lights** (panel: Automatic light timing = All lights): switch a light on: the LIGHTS line first, then
   about 3 game s later `op=enroll ... node=<n> src=build`; the tool shows Keep timing adjusted Yes, and its first
   decision starts from the 4-phase plan (no `op=adopt` right after the enrollment).
6. **A new road** that makes a lit crossroads (Apply automatically On): planned by the automatic pass as before (`WRITE
   ... sl_plans=` / `PHASES src=auto`), no `src=new_light` line for it.
- **Re-check after the 2026-10-16 fix** (first try: every light skipped, no reason logged): switch on a light at a
  1-lane T-junction and at a 2-lane crossroads: `AUTORETIME op=plan_new src=build sent=1`, `LIGHTS src=new_light`.
  Any `skipped=` count names its reason in `why=`; send it along if a light that should have been planned was not.

## NC. No classic fallback: the game's phases where no axis plan can be made (PLAN.md "No classic fallback"; 2026-10-16, offline only, not run in game yet)
Read back with `make logs-grep PAT='PHASES|LIGHTS' ARGS='--session live'`. Setup: Light phases = Smart Lanes (mod
option or the in-game settings panel), "No lights at roundabouts and ramps" as you like, a town with traffic.
1. **5-arm lit junction.** Build a junction of five two-way roads and switch its light on in the Crossing Tool (or let
   the game light it). Its phases stay the game's (Crossing window: the engine's phases, not one phase per road plus
   6 s pedestrian phases); the log has `[SQRL] SKIP kind=slip node=<n> reason=roads_5` after a build there and no
   `PHASES` line for that node (a 5-arm junction is not handled: no lane write, no plan). Select it with the Smart Lanes tool: the light row shows Re-time (and Keep timing adjusted) only,
   **no Smart lights button**; the detail line ends "Smart lights: not for this junction shape". Re-time still works
   there (durations only).
2. **Skewed lit crossroads.** Build a crossroads whose cross road meets at a sharp angle (one pair of arms more than
   45 deg off a straight line, e.g. a road crossing at ~30 deg) with a light, Light phases = Smart Lanes. After the
   build (or Smart lanes in the tool): `[SQRL] PHASES src=auto|tool node=<n> phases=sl pattern=none
   plan_fail=no_axis_shape`, SUMMARY `plan_fail=no_axis_shape:1`; the Crossing window shows the game's phases
   re-pointed onto the new lanes (6 phases), traffic runs. Select it: no Smart lights button, the detail line
   "Smart lights: not for this junction shape". de / ru: the text fits (it wraps in the info block).
3. **Normal crossroads unchanged.** A lit right-angle 2x2 crossroads next to it: `PHASES ... pattern=axis plan=x4_axis
   cycle=60`, Smart lights shown, then hidden right after the write (the badge "√ Smart lanes | √ Smart lights").
4. **Stress Test.** Build Light plans A/B: zones go out without `sl_classic` (`ZONES op=set ... by_ab=game:6,sl:0,
   sl_phases:6,sl_auto:6`), no `ab<i>` refusal. Open: a lit T-junction bench, game vs axis (PLAN.md "No classic
   fallback").
5. Report: the PHASES / SUMMARY lines of steps 1-3, a screenshot of the tool at the 5-arm junction (no Smart lights).
6. **The user's junction (node 32350, session `2026-10-17_0057_sqrl-sqsg`).** A lit crossroads with arms at about 20 /
   146 / 184 / 274 deg (arms B / D 52 deg off a straight line; the game gives it 8 phases: A+C, D alone, B alone). Select
   it: no Smart lights button from the start, the detail line "Smart lights: not for this junction shape"; Smart lanes
   (the lanes) shown. Smart lanes: `APPLY ... lit=yes`, `PHASES src=tool node=<n> phases=sl pattern=none
   plan_fail=no_axis_shape` (no `action=lights_only`: the lane button's line), the Crossing window keeps the game's 8
   phases re-pointed. Then Smart lanes is hidden (the badge "Smart lanes"), Reset shown; still no Smart lights.

## RH. Reset hides after a Reset (PLAN.md "Reset hides after a Reset"; 2026-10-16, offline only, not run in game yet)
1. A lit T-junction or crossroads: Smart lights, then Reset: `LIGHTS src=reset ... to=game_phases`. Within a second
   Reset is gone (Smart lights and Re-time stay). Select another junction and back: still gone.
2. With Keep timing adjusted Yes there: once it adjusts the timing (`AUTORETIME op=write node=<n>`), Reset is back.
3. Save, load, select it: note whether Reset shows (it may: the engine's flag after our Reset is not known).

## IO. Idle runtime and Automatic light timing Off (PLAN.md "Idle runtime and Automatic light timing Off"; 2026-10-17, offline only, not run in game yet)
Debug: performance log On (SQPERF sections `auto`, `gui_update`, `update`).
1. A big saved city, Junctions I choose, nothing enrolled (the welcome answered Not now): play 10 min at 4x. SQPERF
   `auto` avg near 0 and max under ~0.2 ms; no `AUTORETIME op=snapshot` line; no stutter.
2. Console, the stamp read the GUI poll now uses (GUI thread): `local gs = api.engine.getComponent(
   api.engine.system.gameScriptSystem.getEntityForGameScript("square_smart_lanes::/smart_lanes/sl_lanes.gs"),
   api.type.ComponentType.GAME_SCRIPT); print(gs.state_native:find("seq"), gs.state_native:find("aseq"))`: numbers (or
   nil in a save without jobs), no error. Then build a roundabout: its lanes are set as before (the poll saw the job).
3. Smart Lanes tool, select a lit crossroads, Keep timing adjusted Yes: within a second the status reads "counting
   waiting cars (0 of 8)"; snapshots follow (`op=snapshot ... n=1`).
4. Nothing selected, Automatic light timing Off: `AUTORETIME op=mode mode=off ... unenrolled=0`, status "Light
   timing: off"; the junction from 3 shows "paused while Automatic light timing is Off", its toggle still Yes. 10 game
   min: no `op=snapshot` / `op=write`. Back to Junctions I choose: `unenrolled=0`, counting starts again.
5. Mod settings: Automatic light timing Off, load the save: as in 4 without the panel; the panel shows Off.

## NJ. Nearby junctions stay as they are (PLAN.md "Nearby junctions stay as they are"; 2026-10-17, offline only, not run in game yet)
Apply automatically On. `make logs-grep PAT='\[SQRL\] (APPLY|SKIP|SUMMARY|LIGHTS)' ARGS='--session live'` after each step.
1. A lit crossroads with the game's lanes (none of ours): build a new road that joins one of its arm roads halfway
   (more than ~80 m from the crossroads), not at the crossroads. Expect `SKIP kind=cross node=<crossroads>
   reason=unchanged` and `skips=unchanged:1` in the job's SUMMARY, no APPLY for it; the Crossing Tool shows its lanes
   unchanged. If an APPLY for it still appears instead, the event's `removedSegments` lack the edge data the rule
   compares (typeIndex, lanes): note it and paste the lines.
2. The same with a crossroads that has Smart Lanes' lanes (lit, free curb turn Always): no APPLY and no SKIP for it;
   the tool still shows Smart Lanes' lanes (the engine kept them). Note whether a `LIGHTS src=auto node=<it>
   to=free_turn` line follows (the rebuild locked its curb turns back: docs/findings/roads.md "A replaced arm keeps the
   junction's lanes"); with Light phases = Smart Lanes, whether `to=sl_phases` follows and the phases are the plan.
3. Build a fourth arm onto a T-junction (the road ends at the junction itself), and upgrade one arm road of another
   crossroads to another street type (street upgrade tool): both get their lanes as before (APPLY for each).
4. A Smart Lanes roundabout: join a road partway along one of its arm roads, away from the ring. Expect the whole ring
   planned (`SUMMARY ... rings=1`, `ring=0/4/0` or APPLY on every arm junction as needed), no LIGHTS line for that
   arm's junction.
5. A street stop placed on an arm of a crossroads, ~30 m out (the stop rebuilds the arm): it is still handled
   (`APPLY ... open=<arm>:stop`, as OE step 2), no `reason=unchanged` for it.

## AP. Which part of the timing runtime makes a slow frame (PERF_REVIEW.md 2026-10-17 "9 ms frames"; added 2026-10-17)
Debug: performance log On. A city save, Automatic light timing All lights (100+ lit junctions), Light phases Smart
Lanes; play 10 min at 4x and build a few streets with lights. Then `make perf ARGS='--mod square_smart_lanes'`: in
ctx=bg, the `auto_*` section whose `max` is near `auto`'s max is the culprit (`auto_new` the new-light look,
`auto_write` a timing write, `auto_looks` refreshes and decisions, `auto_list` the listing, `auto_snap` a snapshot,
which should stay at ~1 ms). Report its max and calls; that part gets a clock budget next.

## RM. Removing the mod from a save with saved state (rev 8 release check; added 2026-10-14, not run yet)
Rev 8 keeps more lists in the game-script state (`kept`, `auto`, and `rlast`, the per-junction last-measured records of
both Re-time modes, step B v4; `trec`, the last traffic recordings, TR). Expected: the game drops a removed script's state; the written lanes and phase lengths stay as
ordinary data. Check before releasing rev 8:
1. Load a save where "Keep timing adjusted" ran and a manual Re-time wrote (status shows "Last measured ...").
2. Save, turn Smart Lanes off in the mod list, load that save.
3. Pass: no Lua error or assert mentioning square_smart_lanes in the log (`make logs-grep PAT='square_smart_lanes|assert' ARGS='--session live'`),
   the lit junctions keep their last phase lengths and cycle normally. Record the result in docs/findings/scripting.md.
