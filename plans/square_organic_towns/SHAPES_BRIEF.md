# Shapes round: brief (2026-10-12)

Start after the street-hierarchy round (NEXT_PHASE_BRIEF section 11) is in: both touch ot_select / ot_core /
ot_style. One subagent. Read first: PLAN.md 6.3 (shapes, `ot_shape`), NEXT_PHASE_BRIEF 9-11, TESTING.md
"Showcase v4", docs/findings.md 2026-10-11/12 entries.

## Why
User (2026-10-11): towns should not all radiate from the centre: long and skinny, wide, spidery, coast-hugging,
valley-winding. Showcase v4 (2026-10-12, Blank Slate, flat): the shape row (compact, linear, cross, fingers, fan,
twin, lens, ridge) all read as **round blobs** in the top-down shots (`.cache/ot_shots/2026-10-12_08-02-54/
29-44-*.png`). Offline metrics had improved (linear elongation 2.7 -> 6.0), in game they don't show.

Numbers from the log (SHOWCASE STEP step=10/10): each shape town ends at ~225-300 edges, of which the game-made
core is ~85-95 and the mod built ~10 increments of ~16 edges; ~600 buildings; the town is ~1 km across. The
game also grows its own streets (`vanilla=` field).

## Likely causes (check each, measure, don't guess)
1. Growth all round: the selector's open-frontage / gap filling picks pieces on every side of the round core, so
   a shape preference only skews an even ring.
2. Steering is a cost modifier, too weak against distance-from-centre ordering.
3. The round game-made core is a third of the town after 10 steps; a shape needs reach (2-3x the core radius
   along the axis) before it reads.
4. Forced growth (UpdateSize) fills around the core evenly, and vanilla street growth adds round.
5. Increment size / lead cap / growth front (section 10 and 11) stop the long axis from reaching out.

## Goals
- At 10 showcase steps from a vanilla core, on flat land, the shape row is recognisable from the top-down tour
  shot: linear clearly long (elongation >= 3 measured on built streets + houses, not just mod edges), fingers =
  3-5 distinct arms with empty wedges, fan one-sided, twin two lobes, cross 4 arms, ridge along its line,
  lens oval.
- Growth goes where the shape wants: e.g. most of an increment along the axis / arms; gap filling inside the
  shape's envelope only, not beyond it on the "wrong" sides. Consider an envelope per shape (allowed region
  that grows with town size), hard-limiting new pieces outside it.
- Houses follow: wedges stay empty only if no streets go there; check whether forced growth builds along our
  streets (density follows our network) rather than around the centre.
- Keep realism: no 2 km empty spurs (lead cap stays), the street hierarchy from section 11 stays, no
  zig-zags / lassos.
- Auto picking in normal games stays mild (site / roads / neighbours decide); strong shapes where the site
  says so (coast -> hug the shore, valley -> along it, ridge -> along the crest). The showcase forces shapes.

## Measure
- `ot_metrics`: elongation, arms count, one-sidedness, envelope fill, on the whole town (vanilla core + mod),
  offline simulate 10 and 20 increments from a vanilla-like round core; before/after table per shape.
- Log a `SHAPE` line per increment in game (shape, axis, metric values) so the next showcase log tells the
  story without screenshots.
- SVG previews (`tools/ot_preview.py`, `svg/shapes/`).

## Also fold in (small, same showcase run)
- Settle: forced growth passes on by default during Settle (v4: 5 game months at speed 4 in 6 min added 22
  buildings to 30 towns; towns without transport barely grow). Tour should wait for Settle to end (user started
  the tour mid-settle).
- Density "upgrade" once at step 3 had no effect (buildings 306->306, capacity 1302->1308): find out why
  (position? upgrade needs demand?) or drop the lever.
- Starting angle: every showcase town reads back givenAngle=35 whatever it asked for, and the Probe C towns
  0/15/45/90 look identical (organic). TownInfo angle isn't applied to `makeTownCreateCmd` mid-game, or the
  read-back is wrong. Record in findings; check whether the showcase can create towns another way, else
  drop the Probe C row and note it. Map-creation angle (preRunFn) stays to be tested on a new map.

## Locking the game's own street growth (user asked 2026-10-12)
- Per street: no command sets `roadDevelopmentLocked` on an existing edge; a proposal can only set it by removing
  and re-adding the edge, which demolishes its houses (PLAN.md 4 / HANDOFF D4). Not an option for existing
  streets. Check whether setting it on our own NEW edges is useful (it would stop the game extending our tips,
  not stop it building elsewhere). User (2026-10-12) quoted that a locked street stops the town modifying,
  upgrading or attaching new side streets to that segment: that makes it worth a probe for our own new edges on
  the shape's envelope / wedge sides (lock set in the proposal, no rebuild): does the town still build houses
  along a locked street (needed), and does it stop vanilla side streets off it. Also stops the game widening our
  narrow local streets. Showcase v5: one locked twin of a shape town. Find the field name in the street
  proposal / edge component tealdefs.
- Per town: the showcase "Freeze style towns" toggle (makeTownSetDevelopmentActiveCmd false) exists but has never
  run (v4 log: freeze=false). Turn it on for the shape row in Showcase v5 (or a frozen twin of each shape) and
  measure: does forced UpdateSize still add vanilla streets, do houses still fill along our streets.
- v4 `vanilla=` per shape town was small (-16..+10 edges over 10 steps): the round outlines come mainly from our
  own selector, so the envelope / strong steering is the main fix; freezing is the backup.

## Rules
Every new node needs a BASE_NODE_CONFIG; lane indices valid for mixed widths; don't impact saves (saved plan
frames load); no new user-visible strings without all 13 languages (dev mod exempt). Run only `make test
MOD=mods/square_organic_towns` and `_dev`, `make check` for both, `make link`. Never commit, never run make
modio / op. Update PLAN.md 6.3, NEXT_PHASE_BRIEF (new section 12), TESTING.md "Showcase v5".
