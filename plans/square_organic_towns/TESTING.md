# Organic Towns: in-game test checklist (Phase 3, NA grid MVP)

In-game checks of `square_organic_towns` (rev 3 published 2026-10-17: free unowned builds, testing growth removed; rev 4 ready: the town window card and the new-town notification, checked in game 2026-10-17, "Rev 4: town window card and new-town notification"). Everything below reads `[SQOT]` lines in the
game's `stdout.txt` (macOS Steam: `~/Library/Application Support/Steam/steamapps/common/Transport Fever 3/…`
or wherever `make perf` finds it). `grep '\[SQOT\]' stdout.txt` shows the whole story.

Before you start:

- `make link` (done by the Phase 3 session). Quit TF3 fully after any code change (old Lua modules stay loaded).
- The old probe mod `square_organic_towns_probe` was deleted (2026-10-12); its probes live in the main and dev mods.
- Use throwaway saves. The mod builds real streets.

## Rev 2: pause and refunds (2026-10-17; PLAN.md 6.2 "Pause and refunds (rev 2)")

A player's report on rev 1: streets built while the game was paused; a new game at $0 went into the red. A short check
before uploading rev 2. Quit TF3 fully first. Debug log On.

1. **Speed read (console, any running game):** paste
   `local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED); print("SQOT_SPEED", gs.speedup, gs.millisPerDay)`
   once running and once paused: `SQOT_SPEED 1 ...` then `SQOT_SPEED 0 0` (read with
   `make logs-grep PAT='SQOT_SPEED' ARGS='--session live'`). **Done 2026-10-17: `0` paused, `4` at x4.**
2. **New game at $0, paused at once** (Act on New towns only, any map; the game's money setting at its lowest, or a
   sandbox start with the Stress Test's booking to 0): pause on the first frame and wait 1 min. Expect
   `[SQOT] PAUSE state=on`, then no INIT / HEAD / CHECK / SEND line while paused, and no new street in town. Unpause:
   `PAUSE state=off pausedS=~60`, then INIT, HEAD start, and the first head-start SEND about 3 s later, not a burst.
3. **Refunds:** every BUILT is followed by `REFUND kind=build ... amount=<about cost> why=paid`, and the balance
   returns to where it was (the Finances window: street construction cost and the same income). `why=notCharged` on
   every line means the callback's balance does not show the charge yet (send it). A lock rebuild keeps its
   `GLOCK event=refund` line and gets no REFUND line. STREETS `refund=` is the session total.
4. **Pause mid-build:** pause right after a SEND line: its BUILT (and REFUND) still comes; then nothing until unpause; no
   `FAILED ... why=timeout` after a long pause.

Lines to send: `make logs-grep PAT='\[SQOT\] (PAUSE|REFUND|SEND|BUILT|FAILED|HEAD|GLOCK town=.*event=refund|STREETS)'`.

## Rev 4: town window card and new-town notification (2026-10-17; PLAN.md 6.2 "Town window card and new-town notification (rev 4)")

Not yet seen in game. Quit TF3 fully first (`make link` done). A **new map** (European list, Landscape names, Town
growth By deliveries, Satellite towns On, Strong town characters On); Debug log On for the summary lines. Use the dev
Simulate (or play a few game years with lines) so towns grow and an offshoot gets founded.

1. **Card appears:** open any town's window. Below District Sizes: a card titled "Organic Towns", collapsed, with one
   header row: the character on the left (e.g. "Hilltop village", or the form name), the phase on the right ("Young").
   **The collapse triangle** (native-UI pass 2026-10-17): it sits at the bottom right, straddling the header's bottom
   border, under the right-hand phase text, as in the base Line window's "Transported" card (same one-line height)
   and the Town Level card (under the growth state). Compare the two: same x, same overlap with the border; the
   triangle must not cover the phase text. The header row's height and top / bottom padding match the Line
   "Transported" card (both a body key / value row in the base card padding). Expand it: the five sections in order
   (Growth by deliveries, Character, Growth phase, Family, Name origin), each heading (bold) under a thin separator
   line (the base one, as between a card's entries) with a few px above and below the line and under the heading;
   nothing touching: a small gap between a row and its bar, a larger one between groups and before a sentence
   (round 2: inline 3 / 6 px spacers, 4 px around headings). Text wrapped inside the card. Log: `[SQOT] CARD
   event=read town=<id> sections=<n> frame=1 ...` once per town per session.
2. **Growth by deliveries:** a town without deliveries: "No deliveries yet ..." in the base info box (tinted, info
   icon, as the base empty states). Deliver industrial cargo to one town for a few game months: a small legend line
   "Share built now → the aim its deliveries set.", then per district a row "Industrial" left, "15% → 70%" right
   (aim below now reads "46% → 43%"; equal: "45%, on its aim") and under it a **thin** bar (round 2: about as thin
   as the Town Level bar at the top of the window, not the thick first-pass bar) in the district's color (as the
   District Sizes chart above), with a 1 px mark at the aim: light where the fill hasn't reached it, dark on the
   fill when the aim is below the built share. Check the mark is visible in both cases; hover: the tooltip explains
   it. Then "Deliveries are pulling this town toward industry."; later "It leans industrial." (compare with its
   `[SQOT] RCI town=<id> ... lean=ind` line). Setting Game default (new game): the "Off in the mod settings" info box.
3. **Character:** a strong-character town (`[SQOT] CHARACTER town=<id> event=apply kind=...`), a deep forest town, a
   secluded one: rows "Town type" / "Form" / "Streets" / "Features" with the value right-aligned and, under each but
   Features, its one-line description in the smaller annotation font (also the row's tooltip). A town without a kind
   (the header shows its form, e.g. "Clustered"): no Form row; the form's description opens the section. Values
   match the town's debug `STYLE` line (`style=`, `form=`; the CHARACTER line's `motifs=` for a kind town). German /
   Russian: the longest row (Streets, Features) stays inside the card.
4. **Growth phase:** "Not measured yet." (info box) until the town's first check. Then the phase's description as a
   sentence (the name is in the header only); on a young / growing-up town a row "Next: Growing up" with "x%" right
   and a thin bar in the Town Level green under it (hover: "x% of the way to the next phase"); a final phase
   (Densifying, Mature, Dense from the start, Stays low): the description only. Debug: `CARD event=summary
   towns=<n>` lines at most every 30 s, only when values moved; the first one always logged.
5. **Family:** on a parent with a district / Works: "Its offshoots:" and one button per town (the base entity-window
   button: card surface, the town icon and the name); click: that town's window opens (stacked, as base links; the
   camera no longer jumps there). On the offshoot: "A residential district, founded by:" / "An industrial Works
   town, founded by:" and the parent's button. A parent without offshoots: "Not ready for an offshoot yet: x% of the
   way." or "Ready for an offshoot when the map has room for one." (check against its `SATPACE ... ready=` line);
   "No offshoots yet." / settings off / a kind without offshoots: the info box.
6. **Name origin:** a renamed town: one "Named for ..." line that fits the name (a "-ford" town: "river crossing", a
   "Lake" name: "the lake beside it"). `CARD event=origins towns=<n> of=<m>` once on the new map. A town with a game
   name or a player's name: no Name origin section.
7. **Notification:** when `[SQOT] DISTRICT ... event=created` / `WORKS ... event=created` appears, a notification pops
   up: "New district: <town>" / "New Works town: <town>" with the parent's name; click: the camera goes to the new town
   and its window opens. Log: `[SQOT] CARD event=notify town=<id> name=... kind=district parent=<id>`. Save, reload:
   no second notification for that town (no second `CARD event=notify` line). The notification log's filter lists
   "Organic Towns: new towns". Look at the icon (district: the base town icon `building_town.tga`; Works: the base
   industry-plus icon): does it look right at the feed's size?
8. **Map editor:** open a town there: no Organic Towns card.
9. **An older save** (made before this revision): the card shows Character / Family where saved data exists, no
   Growth phase, no Name origin, no errors (`[SQOT] ERROR` / `WARN stage=card` none).
10. **Languages:** switch the game to German and Japanese: the card's texts translated, wrapped, nothing clipped.

Record after the run (docs/findings, with the session name): reading a game script's `state_native` from an entity
window plugin (`findPath` on `frames` / `rc` / `ui` / `no`, the GUI state) works or not; a custom notification type's
look (icon size, title / text, click) and whether its entries survive a reload; whether a town window plugin's
`condition` is evaluated per render. Round 2 of the card: whether an inline sheet's `size` / `color` / `backgroundColor1` applies
to a `builtin.ProgressBar` in a card, whether the 1 px threshold mark shows on the 10 px bar, and whether the inline
`size = { 1, h }` gap spacers show (docs/findings/gui.md "Bars in an entity-window card").

Lines to send: `make logs-grep PAT='\[SQOT\] (CARD|ERROR|WARN stage=card|DISTRICT|WORKS)'`.

Run 2026-10-17 22:43-22:49Z (seed A, new map; log not archived): items 1-6 pass, 7 sent once per new town (2 districts,
2 Works), no card errors; state_native reads, inline bars, threshold mark and spacers recorded in
docs/findings/gui.md. Still open: 7's click, icon look and no repeat after a reload, 8 (map editor),
9 (older save), 10 (German / Japanese), and whether `condition` is evaluated per render.

## Name lists from other mods (2026-10-17; NEXT_PHASE_BRIEF 72; PLAN.md 6.2 "Name lists from other mods (§72)")

Not yet seen in game. Needs a German name list from another mod: subscribe to "Deutsche Städte und Gemeinden"
(mod.io german-cities-and-municipalities5; `make subscribed` copies it to `.cache/subscribed/` so its folder layout can
be read), or any other mod's list. Quit TF3 fully first (`make link` done).

1. **New map, dry climate,** the German list, Town style Automatic, Vanilla town street angles Automatic, Town and
   stop names Landscape names, Satellite towns On. Expect `[SQOT] ANGLE ... region=EU regionSource=nameList
   nameList=<modId>::/names/...` (not MED from the dry climate) and `[SQOT] NAMELIST list=<same path> base=false
   region=EU country=germany regionSource=nameList word=<german / deutsch...> cls=de clsSource=country`. If the
   path has no German word: `country=- clsSource=guess cls=de` (from the map's names), else `clsSource=list` with
   `listPath=` and `listN=`, or `clsSource=fallback why=...` (send the line: the list's layout differs).
2. **The list's towns keep their names:** `[SQOT] NAMES on=false why=notBase`, no STOPNAME renames; the map's towns
   carry the list's names.
3. **Satellite names:** play (or the dev Simulate) until a `DISTRICT ... event=created` / `WORKS ... event=created`:
   the new town has a German name ("Ober<parent>", "<parent>-Heide", "<parent>-Hütte"), no English word ("Heights", "Works",
   "Upper"). With `clsSource=list`: an unused name of the list itself.
4. **A missing towns.lua is harmless** (only when step 1 shows `clsSource=list` or `fallback`): `tries=` > 1 and no
   error dialog, no `[SQOT] ERROR`, no assert; note what the game logged for the missing paths (findings).
5. **Base lists unchanged:** a European map shows `NAMELIST ... base=true clsSource=base` and the same names as before.

Console (any running game; read the output with `make logs-grep PAT='SQOT_NL' ARGS='--session live'`): the map's list,
as base copies it into baseConfig (`nameId`, findings towns.md; reading it from the console is untested):
`print("SQOT_NL", api.res.getBaseConfig().nameId)`. Whether another mod's towns.lua loads, and what a missing one
does (replace `<modId>` / `<dir>` with the printed path's parts): `local ok, l = pcall(ug_require, "<modId>::/names/<dir>/de/towns.lua"); print("SQOT_NL", ok, type(l) == "table" and #l or tostring(l))`.

Lines to send: `make logs-grep PAT='\[SQOT\] (ANGLE|NAMELIST|NAMES|DISTRICT|WORKS|ERROR)'`.

## Continuous thoroughfares (2026-10-17; NEXT_PHASE_BRIEF 73; PLAN.md 6.2 "Continuous thoroughfares (§73)")

Not yet seen in game. Quit TF3 fully first (`make link` done). New map, start year 1900, Town style Automatic (or
EU organic), Satellite towns On, debug log On; play (or Quick / the dev Simulate) to about 1920, then on to the
1950s for the late arterials.

1. **No lone medium edges, early:** zoom over a few towns around 1905-1920. Medium streets only as long through
   streets (a high street, the road out to the country road, a street to the station); no single medium edge or
   short medium piece between small streets. `[SQOT] SNAPSHOT ... wideRuns=` per town: `lone0` and `short0` on
   the runs our builds make (a short run may still be the game core's or the game's own: see 3).
2. **PLAN lines:** `hier=wide<n>/.../short<n>` and `runs=<kept>/<cut>/<longest m>`: before 1940 mostly `short`
   counts and `runs=0/...`; a kept run's longest >= 300. BUILT `tipRej=wide:n` when a tip would have been a wide edge.
3. **Who builds medium streets:** `wideRuns=...;mod<n>,game<n>,other<n>`. `game` > 0 means the game's own growth
   built a medium / large street after it started (a §67-locked game street): note the town and look at it (record
   in docs/findings/towns.md). `other` is the town's core and the game's open streets.
4. **Car routes:** watch a few cars / buses through an early town: no detour through a lone medium edge.
5. **Late hierarchy (1950s, NA grid / suburb / superblock, or a metropolis):** arterials still come as long lines
   (PLAN `runs=` kept with longest well over 300), STREETS `wideRuns=` short / lone stay low.
6. **No refusals from the joins:** a small street joining the end of a medium street builds (no `REFUSED` /
   "Construction not possible" at such a joint; mixed widths at a 2-street node, as `wideJoin` already does).

Lines to send: `make logs-grep PAT='\[SQOT\] (SNAPSHOT|PLAN|BUILT|STREETS|REFUSED)'`.

## Wider minimum block (2026-10-18; PLAN.md 6.2 "Wider minimum block")

First seen in game 2026-10-18 (results below). Quit TF3 fully first (`make link` done). A new map with a few MED hill, EU organic and JP dense
towns (Town style Automatic on a European map with hills, or the setting per style), debug log On; play (or Quick / the
dev Simulate) a few decades.

1. **Fewer slivers:** zoom over grown towns. Blocks between two parallel mod streets where only one large building or
   only the smallest buildings fit should be rare now (were frequent in MED hill and EU organic): two neighbouring
   parallel streets about 44 m apart at least (a row of 3-cell lots between them). Cross streets still about a block
   apart, just more evenly spaced. Screenshots of any narrow block left (with the town's style from the PLAN line).
2. **Density about as before:** towns grow as fast and as dense as on the last run (STREETS / CHECK `buildings=` per
   decade); MED hill towns a little less street per house. A town that stops growing for many checks (STALL lines)
   is worth a note with its style.
3. **Deep forest and hug towns** keep their groves (no wider cuts beside the arms).

Lines to send: `make logs-grep PAT='\[SQOT\] (PLAN|STREETS|STALL|CHECK)'`.

**Run 2026-10-18 22:22Z** (session `2026-10-18_2222_sqot`; seed `a`, EU, 1900, dev Quick 40 years, tour; compared
with the §71 run `2026-10-16_1846_sqot` load 2, same seed; compare page `compare/2026-10-15_a-lock`, run `mod-2222`).
No MED hill / JP dense site test: the map has 3 MED hill towns (Seachurch Cove, Wheatden, Ashgrove), the rest EU.
1. **Fewer slivers: not judged.** The tour's overview shots (1800 m) are too far out for block widths. Crops at full
   resolution (Dovemouth, Watersmeet, Dalemere, Two Waters) show no obvious one-row blocks between parallel mod
   streets; narrow blocks are mostly in the game's own curved fill. A close-up pass (dev showcase or zoomed shots) is
   still needed.
2. **Density about as before: pass.** Persons at year 40 44155 vs 44159, capacity 43782 vs 43814, buildings 9212 vs
   9384 (the towns build bigger: pb median 4.86 vs 4.77), persons / ha median 39.3 vs 34.7, median radius 457 vs 495 m,
   `spread` 1.23 vs 1.36. Mod street built 100.1 vs 108.5 km (planned length 27.8 vs 30.1 km, SEND edges 926 vs 955 to
   the SIMGROW stop); the game's own street length 104.1 vs 100.5 km (share 0.51 vs 0.48: Seven Oaks 9.6 vs 5.4 km,
   Two Waters 14.1 vs 9.9, Seachurch Cove 8.1 vs 3.5, Lower Arunmouth 9.0 vs 5.7). MED hill street per house: Wheatden
   13.6 vs 16.0 km for 597 vs 628 buildings, Seachurch Cove 14.5 vs 11.1 km for 678 vs 552. **0 STALL**, 2 STUCK
   (Little Dalemere year 31 `emptyRun=6 held=wedge=1,env=3`, Hornholt Isle year 35 `emptyRun=6 held=lead=1,wedge=4,env=4`;
   the §71 run also had 2: Wheatden, Ashgrove); empty plans 98 vs 107. `frontRelax` / `frontExtra` are not logged
   (ot_select keeps `report.frontRelax` but no line prints it), so whether they fired is unseen. Hornholt Isle's
   buildings fell 345 -> 239 at year 12: a LEVELS set (`was=0.527/0.278/0/0` -> `0.769/1/1/1`, pb 3.35 -> 5.79), not a
   stall; it ended at 443 buildings with the same capacity as before (2755 vs 2739).
3. **Deep forest and hug towns keep their groves: pass (shots).** Dovemouth (deep, `forest=0.35:deep`) keeps the
   woods round it; forestLot sum 29.7 ha vs 30.6 (same count).


## Away from player facilities (2026-10-18; PLAN.md 6.3 "Away from player facilities")

Harbors, airports / heliports, vehicle depots / maintenance stations and freight-only stations the player builds near a
town get a light lean (never a zone, never a hold). The reads are unverified in game. Debug log On, quit TF3 fully first.

1. **Listing (console, any game with a few depots / stations built):** paste
   `local E = ug_require "square_organic_towns::/organic_towns/ot_engine.lua"; local I = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"; local l = E.facilities() or {}; print("SQOT_FAC n=", #l); for i = 1, math.min(#l, 60) do local f = l[i]; print("SQOT_FAC", i, I.classifyFacility(f) or "-", math.floor(f[1]), math.floor(f[2]), f.depot and "depot" or "-", tostring(f.cargo), tostring(f.passenger), f.file) end`
   and read it with `make logs-grep PAT='SQOT_FAC' ARGS='--session live'`. Expect every depot / maintenance station as
   `depot` (file under `depots/`), a harbor as `port`, an airport `airport`, a truck or cargo rail station `freight`
   (`cargo=true passenger=false`), passenger rail stations and bus stops `-`. If `n= 0` with depots on the map, try
   the depot read alone: `local d = api.engine.getEntitiesWithComponent(api.type.ComponentType.VEHICLE_DEPOT); print("SQOT_DEP n=", #d); for i = 1, math.min(#d, 20) do local c = api.engine.system.streetConnectorSystem.getConstructionEntityForDepot(d[i]); print("SQOT_DEP", d[i], c, c and c >= 0 and api.engine.getComponent(c, api.type.ComponentType.CONSTRUCTION).fileName) end`.
   Record the result in `docs/findings/towns.md` (the reads' entry).
2. **In play:** build a harbor (or a road depot, or an airport) 300-500 m from the edge of a town the mod is growing.
   Within ~2 min: `[SQOT] FAC facilities=<n> port=1 ...` (only when the list changed). The town's next PLAN / SHAPE lines
   carry `fac=1:1/0/0/0/0` (port), `zones=` unchanged by it and no extra `indHeld=`. Over a few game years the mod's
   new streets favor the other sides a little (a depot barely, a harbor or airport more), and the town still grows
   toward it when nothing else is left.
3. **Passenger rail station:** build one beside a town: no `fac=` count for it (the M3 station quarter still pulls).

**Run 2026-10-18 22:22Z** (session `2026-10-18_2222_sqot`, fresh seed `a` map, no player facilities): the reader ran
in the mod's script state without error: `FAC facilities=0 port=0 airport=0 heliport=0 depot=0 freight=0 read=15
ok=true us=53-102`, every PLAN `fac=0` (342), no zone or hold. Items 1-3 not tested (nothing built). Oddity: 17
identical FAC lines in the first 3 s (22:23:03-06), although `Driver:facilitiesRead` logs only when the signature
changes: `self.facSig` seems not to persist between those calls; harmless here, but on a map with facilities it may
also redo the towns' share each time. Check it in the next facility test.


## Side streets and parallel streets (2026-10-19; PLAN.md 6.2 "Side streets and parallel streets (§75)")

First seen in game 2026-10-19, again 2026-10-20 (results below: `geoSide=0` and the empty lines' `knotHeld` confirmed,
6. fires without stalls; next run: 5. with the fixed PROV `src` (`nm:<kind>`, `link/conn`, `m:<motif>/...`), `who()`
from the console on a street of this session and again after a save / reload, and shot 5's comb looked for on
screen; since 2026-10-20 also 7. (TICKCOST before / after the state read change), 8. (SNAPSHOT `emptyRows`) and 9.
(CHECK `rBody` / `out`, FRAME `tipCut` / `maxTipR`, PROV `d=`)). Quit TF3 fully first (`make link` done). The 2026-10-19 save with the shots (or a new map), Town
style Automatic, debug log On; play (or Quick / the dev Simulate) a few decades in organic towns (EU organic / EU
extension / MED hill) and at least one forest town.

1. **No shallow side streets (case A):** new mod streets leave a junction at 60 deg or more (a Y fork aside). PLAN
   `geoSide=0` on steer towns of organic styles (grids may show some: exempt), `knotHeld=<n>:<cross>/<parallel>/<loop>/<side>/<row>`
   counts the holds (`<row>` since 2026-10-19, 6.).
2. **No long parallel back streets (case B):** no new mod street runs more than a block length (60-200 m) beside
   another within ~40-50 m without a cross street; PLAN `knotHeld` `parallel` counts. The towns still grow about as
   fast (CHECK `buildings=` per decade; STALL / STUCK as before): the holds never give way, so a town whose PLAN shows
   `edges=0` with only `knotHeld` side / parallel for many plans in a row is worth a note.
3. **Corners close up (case C):** PLAN `nmJoins=pair:<gap>c` (a corner of two dead ends) and `...r` (a join closing a
   retired dead end: the first ever, retiredOk was never passed on before). Over a session expect `nmKept=noJoin` and
   `target` well down against `2026-10-19_0531_sqot-sqrl` (338 / 265 of 962). The forest town by the water: the
   corner south of the T in the shots closes within a few builds unless its draw left it (`chance` / `forest`).
4. **The corners build:** after a `c` join, no `REFUSED` / "Construction not possible"; a right-angle corner node
   between two small streets, houses along both legs later.

5. **Street provenance (2026-10-19, record bounded and who() fixed 2026-10-20; PLAN.md §75 "Follow-ups built"):**
   with the debug log on, every build is followed by one `[SQOT] PROV` line per new edge: `town= name= edge=<entity>
   n=<node0>,<node1> a=<x>,<y> b=<x>,<y> len= src= key= trig= seq= year= lock=` (`src`: `plain/ln` an organic lattice
   cross lane, `plain/sr` a secondary radial, `plain/bk` a back row, `plain/sp` a spoke, `nm:tee` / `nm:pairc`
   near-miss joins, `link/conn` a connector, `m:<motif>/...`, `lead` / `works` / `sat` / `bridge` / `frame`; more than
   24 edges: a `more=` line). To name the builder of a street on screen, hover it and paste **the whole line** in the
   console (the key below Esc; a bare `who()` is undefined there):
   `ug_require("square_organic_towns::/organic_towns/ot_prov.lua").who()`
   (or `.who(<edge id>)`, `.who(<x>, <y>)`); the answer shows in the console (the echoed return value) and in
   stdout: `make logs-grep PAT='\[SQOT\] WHO' ARGS='--session live'`: `ours=yes src=...` (ours, with the piece),
   `ours=likely` (ours, split or rebuilt by the game since), `ours=probably` (locked, no record: built before this
   version or older than the record's ~700 newest edges), a §67 game lock, or `ours=no` (the game's growth or the
   original layout). Check: (a) on a long street (the 0228 miss, `no street within 40 m`) it now names the edge; a
   miss says `the nearest street <d> m`; (b) `ours=yes` for a street built this session and again after a reload
   (`state_native` from the console); (c) an error prints `[SQOT] WHO error ...`, never nothing; (d) TICKCOST `pvB`
   stays at most 32768 over a long session and `getMaxUs` as before the record (1949 / 0001 runs: `getMaxUs`
   180-330; `getAvgUs` now falls, 7.); (e) an old save (no `pv`): `pvB=0` until the first build, no load cost. Then note the console
   facts in docs/findings/debugging.md.
6. **One empty row at a time (2026-10-19, shot 5):** no new comb of empty parallel dead-end lanes ~45 m apart beside
   an empty street of ours: a second row comes once the first has houses, or as a closed block. PLAN `knotHeld` `<row>`
   counts the holds; the empty PLAN and STUCK lines carry it too: a town whose plans stay empty with only `row` holds
   for many plans in a row is worth a note (offline it never stalled a town). CHECK `buildings=` per decade about as
   before; empty street km (the run's table) down.

7. **The saved state off the frame path (2026-10-20; PLAN.md §75 "The saved state off the frame path"):** the game
   script copies the whole saved state only when its change number moved (and after the mod's own events, and every
   2 s), no longer every frame. TICKCOST (always on, every 5 min) before / after: `getAvgUs` from about a copy's cost
   (the 0001 run: `avgUs` 150-230 per tick with the copy inside; `getMaxUs` 166-475) to a few us; `getN=` (full
   copies in the window) from the tick count (~20,000-23,000) to a few hundred; `getMaxUs` about as before (copies
   still run on changes); `avgUs` down by about the copy's mean. `stateMode=rev` on every line; `stateMode=get` or a
   `[SQOT] STATEREAD mode=get reason=...` warning means the session fell back to the old path (say the reason: the
   native read failed, or the cost check found it no cheaper; e.g. `getComponent` copying the state itself).
   `revMiss=` (session total) > 0 means the native number and the copy lag each other (harmless: the mod's own
   events are watched; note the figure). Check also: no `gamescript_util.cpp` assertion and no crash dump (the read
   is the town window card's, on the Main Thread, never `get_native`); growth as before (the same events); after a
   save / load and after loading another save, the towns' frames still read (no style or shape flip at the next
   build: a stale copy would show there). Then note the facts in docs/findings/game-scripts.md.
   **Run 2026-10-20_0424_sqot-sqrl (54 min, existing save "Organic Towns - Subarctic", loaded twice: 04:26 and
   04:29Z):** 9 TICKCOST lines, all `stateMode=rev revMiss=0`, `getAvgUs=13-14`, `getN=250-397` full copies per
   ~17,000-23,000 ticks (~1.5 %), `getMaxUs` 159-233; tick `avgUs` 103-128 vs 214-236 in the 0001 run on the same
   save (about half). No STATEREAD warning, no `gamescript_util` assert, no traceback of ours. `maxUs` spikes
   (41-90 ms at `job:plan`) as before. Record: `pvN=8 pvB=395` (few streets built this session). who() run 8 times
   (05:18-05:19Z): 4 answers (`ours=no` game lock town 55226; `ours=no` x2; `ours=probably`), 4 misses with the
   nearest street 43-149 m from the cursor point (open: was the cursor on a street? the console window may cover it).
   No `ours=yes` yet: none of the 8 recorded streets was picked.
8. **Empty-row measure (2026-10-20):** SNAPSHOT (debug) `emptyRows=<m>/<dead-end m>/<edges>`: the town's own empty
   edges running 40 m+ beside another within the row distance (`rowsUs=` its time, under a few ms). Read it per town
   over the run (last SNAPSHOT per town, summed): the row rule's gain in game (offline: 1.5 -> 0.3 km, dead-end 0.7 ->
   0 km per EU organic town at +15 houses per increment); compare with shot 5's comb if one is seen.

9. **Far-out streets after an extent jump (2026-10-20; PLAN.md §75 "Far-out streets after an extent jump"):** a
   town whose CHECK `r` jumps (1949: Wheatden 478 -> 1070 m; 0205: Seachurch Cove 682 -> 998 m) gets no frame pieces
   out at its outlying houses. Check: (a) CHECK (debug) `rBody=` / `r50=` / `out=<houses>/<groups>` /
   `outFar=<houses>@<m>/<deg>`: on a jumping town `rBody` stays near the old `r` while `r` jumps, `out=` holds the
   outlying group (note its size, distance and heading, and whether its houses stand on a country road or town
   streets; the console line of PLAN §75 for the buildings beyond 700 m); on the other towns `out=0/0` or small
   (note any town with a big second group: a twin, a bridgehead or a forest town split by a gap over 200 m, the
   cases the cap would trim); `bodyUs=` a few hundred us at most; (b) FRAME plan / none lines `tipCap=` /
   `tipCut=<n>[@<m>]` / `maxTipR=` / `bodyOut=`: `tipCut` > 0 only on towns with `bodyOut` > 0 (a cut on a one-body
   town would mean a tip beyond its houses' lead: note it), `maxTipR` <= `tipCap`, frames still come for the armed and
   meadow towns as before (FRAME `outcome=plan` lines about as in 0205: 22); (c) PROV `d=` (the edge
   middle from the town centre): the far plain pieces (`plain/sr`, `plain/conn`, `plain/rg`) of a jumping town show as
   `d=` well past its `rBody` (not capped by this change: the decision on the main body waits for these numbers).

**Run 2026-10-20_0803_sqot (seed `a`, Quick 40, all §75 work incl. the frame cap; vs 0205):** plans 298 (empty 96)
vs 302 (108); knotHeld cross/parallel/loop/side/row 99/15/0/40/37 vs 50/21/1/23/53; knotRelax 12 vs 10; nmJoins
tee/cross/pair 35/12/7 vs 34/8/5; buildings (last CHECK, all towns) 8898 vs 9374 (-5 %; the 1949 run had 8915: within
run spread); PLAN us median/p90/max 44/228/395 ms vs 42/233/517. STUCK 3 (Far Ashworth, Wheatden, Hornholt Isle: held
by wedge / env / forest / armFill, not by knot or row holds) vs 0; REFUSED 3 (precheck collisions / CNP, 1-8 edge
pieces) vs 0; FAILED 1 (Far Ashworth, 18 edges) vs 1; GLOCK `ok=false` 8 (Ashgrove; also 18 / 12 / 10 in the 2222 /
0024 / 1949 dev runs: older). Tracebacks: only the base GUI's expired ReactRef. **Frame cap:** `tipCut` never fired
(no change in this run). **Outlying groups (CHECK `out`/`outFar`):** Dovemouth-in-the-Forest 41 houses @ 3164 m,
Merehythe-on-Redwater 59 in 2 groups (41 @ 1159 m), Seachurch Cove 10 @ 1095 m; every other town `out=0/...`.
**emptyRows** (last SNAPSHOT per town): 13 of 16 towns 0; three with 50 / 166 (89 dead-end) / 182 (182 dead-end) m,
about 0.4 km in all. Verdict: no regression from §75; ready for revision 6.

Lines to send: `make logs-grep PAT='\[SQOT\] (PLAN|BUILT|REFUSED|STALL|STUCK|PROV|WHO|STATEREAD|TICKCOST|SNAPSHOT|CHECK|FRAME)'`.

**Run 2026-10-19 19:49Z** (session `2026-10-19_1949_sqot`; seed `a`, EU, 1900, dev Quick 40 years, tour; against the
§74 "less cautious" run `2026-10-19_0024_sqot` load 1 and the §73 run `2026-10-18_2222_sqot`, same map, read with the
same script; the 16 starting towns compared, each run's new works / satellite towns left out; two user shots taken
mid-run at 19:59:10Z / 19:59:17Z: "shot 4" / "shot 5" below):

| | 2222 | 0024 | 1949 (§75) |
|---|---|---|---|
| plans (with edges / empty) | 271 (- / 100) | 276 (172 / 104) | 285 (172 / 113) |
| PLAN `knotHeld` sum: cross / parallel / loop / side | - | 20 / 0 / 1 / - | 28 / 22 / 2 / 40 (92 pieces) |
| plans with `knotRelax=true` | - | 0 | 3 (each then built only a near-miss join) |
| plans with `geoSide` > 0 | - | - | 6, 1 each (see 1.) |
| `nearMiss` found / joined / kept | 1655 / 20 / 1635 | 1541 / 35 / 1506 | 1423 / 42 / 1381 |
| `nmJoins` (tee / cross / pair; `c` / `r`) | 20 (19 / 1 / 0) | 34 (23 / 10 / 1) | 39 (27 / 8 / 4; 2 `c`, 5 `r`) |
| `nmKept` curve / building / target / noJoin / chance | 454 / 268 / 228 / 200 / 86 | 455 / 461 / 172 / 93 / 86 | 496 / 339 / 139 / 10 / 133 |
| `nmKept` noNode / inc / slope / budget / cut | 183 / 98 / 46 / 3 / - | 36 / 71 / 35 / 24 / 6 | 72 / 68 / 61 / 11 / 11 |
| REFUSED / FAILED / CNP / Lua error | 0 / 1 / 0 / 0 | 0 / 3 / 0 / 0 | 2 / 1 / 0 / 0 (none with a join) |
| STUCK | 2 | 3 | 3 (Hornholt Isle, Far Ashworth, Ashgrove: `held=wedge,env`) |
| PLAN `us=` median / p90 / max | 48 / 224 / 462 ms | 42 / 193 / 398 ms | 38 / 224 / 494 ms |
| 16 towns: buildings / capacity | 9212 / 43782 | 8911 / 44342 | 8915 / 43720 |
| 16 towns: street / mod street / empty street (km) | 197.1 / 97.3 / 47.6 | 196.0 / 106.1 / 49.2 | 190.7 / 95.9 / 44.1 |
| 16 towns: dead ends / median radius | 305 / 457 m | 331 / 474 m | 325 / 467 m |

1. **No shallow side streets: pass.** 40 pieces held as `side` and 22 as `parallel` over 285 plans. `geoSide=1` on 6
   plans (Lower Arunmouth, Seachurch Cove, Watersmeet, Little Dalemere x2, Norfield), every one a plan with a
   near-miss join, 5 at `minAngle=60.00`: a T's heading is clamped to exactly TEE_MIN_DEG 60 and the built tangents
   read back a hair under it (the sixth, Little Dalemere `cross:25` at `minAngle=40.43`, likely the same). Fixed in the
   checker's report (`ot_check.SIDE_TOL` 0.1 deg; test_side75): the next run should show `geoSide=0`. No grower piece
   under 60 deg in the logs.
2. **No long parallel back streets: pass on the holds; the growth cost is small.** Mod street 95.9 km vs 106.1 (0024)
   and 97.3 (2222); buildings 8915 vs 8911, capacity -1.4 %; empty street 44.1 vs 49.2 km. 3 STUCK as before (wedge /
   env holds). Whether side / parallel holds ever emptied a plan could not be read: the empty PLAN and the STUCK lines
   had no `knotHeld` (fixed: both carry `knotHeld=<n>:<cross>/<parallel>/<loop>/<side>`, the empty PLAN line also
   `knotRelax`; `ot_driver.knotText`, test_forced). The 3 relaxed plans built only near-miss joins (Seven Oaks: its
   parallel hold stayed after the relax, as designed).
3. **Corners close up: pass.** `nmJoins` 39 (0024: 34): 4 `pair` (0024: 1), 2 of them corners (Watersmeet `pair:64c`,
   Seachurch Cove `pair:54cr`), and 5 joins closing a retired dead end (`tee:60r`, `tee:44r`, `tee:42r`, `pair:54cr`,
   `pair:33r`), the first ever. `nmKept=noJoin` 338 -> **10** and `target` 265 -> **139** against the 0531 baseline
   (35 % -> 0.7 % and 28 % -> 10 % of the near misses); against 0024 noJoin 93 -> 10, target 172 -> 139. Left:
   `curve` 496, `building` 339, `chance` 133 (more candidates reach the roll), `noNode` 72.
4. **The corners build: pass.** Every join build `BUILT ok=true` (docs/findings/towns.md); the 2 REFUSED (pre-check
   Collision) and the FAILED one were 1-edge plain pieces. A close look at a corner is still open.
- **Frame time:** median lower, p90 / max a little up (224 / 494 vs 193 / 398 ms: the chain walks). SQPERF: nothing of
  ours (only the minimap's).
- **Oddity:** Wheatden's radius 448 -> 1125 m (empty street 4.5 -> 7.4 km, dead ends 9 -> 34) with Wheatden Foundry
  (a new works town 1.5 km off, created after the jump) this run; looked into 2026-10-20: an outlying group of the
  town's own houses, not the Works (PLAN.md §75 "Far-out streets after an extent jump").
- **User shots (mid-run; the log can't name the town: no camera line outside the tour, no per-edge geometry):** shot
  4, a triangle island (~40 x 60 m, three houses) where a street bends 90 deg and a chord cuts the bend; shot 5, three
  long empty straight dead ends ~45 m apart on open grass with a comb of two short streets off the middle one.
  Diagnoses and proposed fixes: PLAN.md §75 "Follow-ups after the 2026-10-19_1949 run".

**Run 2026-10-20 02:05Z (row rule + provenance)** (session `2026-10-20_0205_sqot`; seed `a`, EU, 1900, dev Quick 40
years, tour; the same map as 1949 (same town ids and positions, 16 starting towns: 12 EU organic / MED hill, 3 EU
extension); read with the same script as the 1949 column. The matching point: both are one dev Quick run from 1900 to
year 40 (1901-1940), Quick itself ~2 min in both; the 1949 session ran on into other loads (1h36m), but its 16
starting towns exist only in the first, so both columns cover the same 40 simulated years. Town end figures from the
tour's ALLTOWN lines at year 40):

| | 1949 (§75) | 0205 (+ row, provenance) |
|---|---|---|
| plans (with edges / empty) | 285 (172 / 113) | 302 (194 / 108) |
| PLAN `knotHeld` sum: cross / parallel / loop / side / row | 28 / 22 / 2 / 40 / - (92 pieces) | 50 / 21 / 1 / 23 / **53** (148 pieces) |
| plans with a `row` hold (with edges / empty) | - | 44 (32 / 12) |
| plans with `knotRelax=true` (with edges / empty) | 3 / not logged | 3 / 7 |
| empty plans with a knot hold (cross / parallel / row pieces) | not logged | 37 of 108 (9 / 6 / 12) |
| plans with `geoSide` > 0 | 6 | **0** |
| `nearMiss` found / joined / kept | 1423 / 42 / 1381 | 1666 / 52 / 1614 |
| `nmJoins` (tee / cross / pair; `c` / `r`) | 39 (27 / 8 / 4; 2 `c`, 5 `r`) | 47 (34 / 8 / 5; 1 `c`, 1 `r`) |
| `nmKept` curve / building / target / noJoin / chance | 496 / 339 / 139 / 10 / 133 | 609 / 261 / 278 / 28 / 124 |
| `nmKept` noNode / inc / slope / budget / cut | 72 / 68 / 61 / 11 / 11 | 69 / 77 / 70 / 14 / 0 |
| REFUSED / FAILED / CNP / Lua error | 2 / 1 / 0 / 0 | 0 / 1 / 0 / 0 (FAILED: Monkton, a 5-edge frame wedge, no msgs) |
| STUCK / STALL | 3 / 1 | **0** / 3 (Dovemouth-in-the-Forest, valve fires as in 1949) |
| PLAN `us=` median / p90 / max | 38 / 224 / 494 ms | 42 / 233 / 517 ms |
| 16 towns: buildings / capacity | 8915 / 43720 | 9340 / 44165 |
| 16 towns: street / mod street / empty street (km) | 190.7 / 95.9 / 44.1 | 201.6 / 106.2 / 47.6 |
| 16 towns: the mod's own empty street, last PLAN `ownEmpty` summed (km) | 14.1 | 16.6 |
| 16 towns: dead ends / median radius | 325 / 467 m | 333 / 500 m |
| PROV lines (= BUILT edges) | - | 994 (= 994 in 216 builds; no `more=`, no edge twice) |

5. **Street provenance: lines pass, `src` was wrong (fixed).** One PROV line per built edge (994 = the BUILT
   `edges=` sum), no `more=` (no build over 24 edges), no edge id twice, all `trig=demand`, `lock=1` 898 / `lock=0` 96.
   But `src` never named an origin or a near-miss kind: `plain/sr` 140, `plain/ln` 135, `plain/conn` 112, `plain/rg`
   100, `plain/nm` 72, `plain/sp` 48, `plain/mvgL` 26, `plain/bk` 26, ... beside `frame/frame` 211, `lead/lead` 33,
   `works/*` 11, `bridge/br` 4. Cause: `ot_proposal.build` copied the plan edge into the spec edge field by field and
   dropped `origin`, `nearMiss`, `nearMissKind`, `nearMissCorner`, so `ot_prov.source` saw every plan piece as `plain`
   (test_prov had fed it hand-made spec edges). Fixed 2026-10-20: the spec edges carry those four fields (not read by
   the engine); test_prov +1 through `ot_proposal.build` (`link/conn`, `nm:pairc`, `m:village_green/mvg`). The saved
   record of this run holds the old `src` text for its edges. **Not seen yet:** no `[SQOT] WHO` line in any archived
   session (the console helper never run), no reload in this session, and `2026-10-20_0001_sqot-sqrl` started at
   17:01 local, before ot_prov existed (17:17; its PLAN lines carry the old 4-count `knotHeld`): the console lookup
   and the record after a reload are still open.
6. **One empty row at a time: fires, costs no growth; its gain is not readable from the logs.** 53 pieces held as
   `row` in 44 plans (15 % of the plans), in 9 of the 16 towns (Watersmeet 12, Woodfield 9, Seachurch Cove 7,
   Hornholt Isle 7, Lakeside 6). No town stalled on it: 0 STUCK (1949: 3, `wedge,env`), the longest run of empty
   plans with a `row` hold 3 (Woodfield, 8 empty plans with one `row` piece held, each beside `wedge` / `env` / `lead`
   holds and a reach of 8-11 pieces; it still went 134 -> 481 buildings), empty plans 108 vs 113, plans with edges 194
   vs 172, buildings +4.8 %, capacity +1.0 %. But the town-level empty figures did not fall: the mod's street +10.7 %
   (95.9 -> 106.2 km), all empty street +7.9 %, the mod's own empty street (PLAN `ownEmpty`) 14.1 -> 16.6 km;
   within the run-to-run spread (2222 -> 0024: mod street +9 %) and not the measure the rule targets (empty parallel
   rows; the logs carry no houses per edge). Shot 5's comb needs a look on screen or a log measure.
1. **No shallow side streets: pass.** `geoSide=0` on every plan (the `SIDE_TOL` fix); `side` holds 23 (1949: 40).
- **Joins:** 47 (1949: 39), all built (0 REFUSED); `target` 139 -> 278 and `noJoin` 10 -> 28 (spread over the towns,
  Lakeside 64 as in 1949's 60; the same dead ends counted plan after plan); `r` 5 -> 1, `c` 2 -> 1.
- **Frame time:** PLAN `us=` +5-10 % (the row check's walks): fine.
- **Wheatden-like:** Wheatden normal this time (radius 500 m, 18 dead ends); instead Seachurch Cove (MED hill) went
  radius 649 -> 998 m between two CHECKs at 1928-1936 with 374 -> 481 buildings (1949: 516 m at the end), and its 1940
  builds landed 750 m and 1190 m from the town (secondary radials / a connector, `plain/sr`, `plain/conn`); Merehythe
  and Dovemouth's 1936 frame pieces ~950 m out. The town's extent jumps first, then the mod builds out there. Looked into 2026-10-20
  (PLAN.md §75 "Far-out streets after an extent jump"): another town's houses ruled out (`foreignLen=0`, the extent
  counts only the town's own buildings); an outlying group of its own houses pulled the 90 % radius out, then plan
  pieces (within the lead limit of those houses) and frames (no outer limit) followed. Open: whether the outlying
  houses stand along a country road (console: the town's buildings beyond 700 m, PLAN §75).


## Close the gap (2026-10-17; NEXT_PHASE_BRIEF 74; PLAN.md 6.2 "Close the gap (§74)")

First seen in game 2026-10-18 (results below). Quit TF3 fully first (`make link` done). New map (or a save whose towns the mod acts on), Town
style Automatic or EU organic, debug log On; play (or Quick / the dev Simulate) a few decades. The joins come with the
mod's own builds (at most 2 per build), so watch towns that grow.

1. **The three cases close up, now and then:** zoom over grown towns. Stubs ending a few metres short of a street now
   and then end in a T at a street node; two dead ends curling past each other get joined by one bend; a stub beside a
   junction joins the street ahead. Not every one: far ones (60-80 m) mostly stay, some in the woods stay on purpose.
   PLAN `nearMiss=<found>/<joined>/<kept>`, `nmJoins=tee:25,pair:34` (kind and gap; §75: `c` a corner, `r` a
   retired dead end closed), `nmKept=` the reasons.
2. **The T works (the first config rewrite at a street node with through traffic):** after a `nmJoins=tee:` or
   `cross:` build, no `REFUSED` / "Construction not possible", no assert / crash; cars and buses go straight through
   the street and turn into the new one both ways (no red dead-end sign, no U-turns at the node). Note the node in
   docs/findings/towns.md either way.
3. **No houses lost:** a build with a join shows no drop in the town's buildings (CHECK `buildings=` before / after),
   and `preCost` on SEND stays near the other builds' (a join over a house is refused by the pre-check: `REFUSED`
   then the key `nm:<D>:<N>` stays out for the session).
4. **Looks:** joins read as streets (gentle bends, a T near square), no slivers or knots next to them, no join across
   the gap toward a neighbouring town, none over water.
5. **Frame time:** PLAN `us=` (the whole plan) stays in its usual range; the pass has an 8 ms budget (`nmKept=budget`
   when it runs out).
6. **What stays:** `nmKept=noNode:n` (the street ahead has no node in reach: a T there needs an edge split, not built)
   and `curve` / `target` show what the next step would gain; send a few PLAN lines.

Console (a street node of a town street, to see its lane connections before / after a T; replace `<node>`; read with
`make logs-grep PAT='SQOT_NM' ARGS='--session live'`):
`local c = api.engine.getComponent(<node>, api.type.ComponentType.BASE_NODE_CONFIG); print("SQOT_NM", c and #c.laneConnections, #api.engine.system.streetSystem.getNodeStreetSegments(<node>))`

Lines to send: `make logs-grep PAT='\[SQOT\] (PLAN|SEND|BUILT|REFUSED|STREETS|ERROR)'`.

**Run 2026-10-18 22:22Z** (session `2026-10-18_2222_sqot`; seed `a`, EU, 1900, dev Quick 40 years; the §71 run
`2026-10-16_1846_sqot` for comparison):
1. **The cases close up now and then: partly.** PLAN `nearMiss=` summed over 271 plans: 1655 found / 20 joined /
   1635 kept (the same dead ends counted again plan after plan). `nmJoins`: 19 `tee` (gaps 19, 20, 20, 25, 28, 29, 31,
   31, 33, 33, 35, 41, 44, 44, 45, 47, 64, 67, 68 m), 1 `cross` (42 m, Far Ashworth), **0 `pair`**. `nmKept`: curve
   454, building 268, target 228, noJoin 200, noNode 183, inc 98, chance 86, slope 46, forest 45, green 15, road 6,
   budget 3, taken / spacing / gap 1. Dead ends on the 16 towns 305 vs 353 (dead ends per km median 1.56 vs 1.61). The
   Ts can't be picked out in the 1800 m overview shots.
2. **The T works: pass (build), routing not seen.** All 17 join builds `BUILT ok=true` (e.g. Seachurch Cove 22:23:11
   `tee:28`, Dalemere 22:23:44 `tee:19`, Far Ashworth 22:24:41 `cross:42`), 0 REFUSED in the session, no assert, a
   normal shutdown at 22:26:23Z (~28 fast simulated years after the first T). No cars in this run: routing through the
   node is still open. Recorded in docs/findings/towns.md.
3. **No houses lost: pass.** Buildings CHECK before -> after a join build fell in 6 of 17 builds (-11 in all: Seachurch
   Cove 127 -> 125, Watersmeet 232 -> 228 ...), the same rate as the other 145 builds (44 fell, -155). SEND `preCost`
   median 38306 (join) vs 32156 (other); per edge 5768 vs 9281. No `nm:` refusal.
4. **Looks: not judged** (overview shots only; no join across a town gap or over water in the logs' targets).
5. **Frame time: pass.** PLAN `us=` median 46.3 ms, p90 220 ms, max 462 ms vs 44.8 / 219 / 640 ms in the §71 run;
   `nmKept=budget` once (Wheatden, 3 kept).
6. **What stays:** `noNode` 183 and `curve` 454 are the big ones; `target` 228. A side T (edge split) and a looser
   curve rule would gain the most; why no `pair` ever passes is worth a look.

**Next run: less cautious (2026-10-18; PLAN.md §74 "Less cautious").** Same setup (seed `a`, Quick 40 or play); compare
with the run above (`2026-10-18_2222_sqot`). Kink 45 deg, arcs from 74 m, target nodes to 100 m, 8 shapes on the
place checks, chance 0.97 to 25 m -> 0.4 at 80 m, retired own stubs closable, new kept reason `cut`. Offline the
joinable share rose 87 -> 116 of 267 near misses and the expected joins under the chance 36.8 -> 67.2.
1. **More joins:** `nmJoins` summed over the session clearly above 20 (offline about 1.8x); gaps up to ~100 m now
   (a node past 80 m when the street ahead is within 80 m). `nmKept`: `chance` and `noNode` well down, `curve` down;
   `building` / `target` may rise (more candidates reach the place checks). `noJoin` drops by the snapshot's cut, now
   `cut` (about 2 per snapshot in the last run).
2. **Pair joins appear:** at least a few `nmJoins=pair:` (two stubs closed by one bend, often a retired own stub:
   SNAPSHOT `noJoin=retired:` falls after them). Zoom on one: one smooth bend, at most a 45 deg corner where it meets
   each old street.
3. **No refusals, no assert:** 0 `REFUSED` with an `nm:` key, no "Construction not possible", no crash; a retired
   stub's join builds like any dead end's (its config rewritten: no red dead-end sign at either end).
4. **Looks:** the 45 deg corners at the old dead ends read as a bend in the street, not a kink; the 90-100 m joins
   read as a street of the block, not a long diagonal; none over water, none across a town gap, none through houses
   (CHECK `buildings=` before / after a join build no worse than other builds, `preCost` similar).
5. **Frame time:** PLAN `us=` median / p90 / max near the last run's 46 / 220 / 462 ms; `nmKept=budget` rare.
6. **Routing (still open):** with vehicles running, cars through a T'd street node both ways (no U-turns at it).
7. **Side T:** not built (deferred: an edge split needs a console probe of a housed town edge first). `noNode` left
   shows what it would add.

**Run 2026-10-19 00:24Z (less cautious)** (session `2026-10-19_0024_sqot`, load 1; seed `a`, EU, 1900, dev Quick 40
years, tour; against `2026-10-18_2222_sqot`, both read with the same script, so the 2222 medians differ slightly from
the block above):

| | 2222 | 0024 |
|---|---|---|
| PLAN `nearMiss=` found / joined / kept (sum over plans) | 1655 / 20 / 1635 (271 plans) | 1539 / 35 / 1504 (274 plans) |
| `nmJoins` entries (tee / cross / pair) | 20 (19 / 1 / 0) | 34 (23 / 10 / 1) |
| join builds (plans with a join) | 17 (18) | 32 (32) |
| join gaps | 19-68 m | 26-95 m, 4 over 80 m (tee 81, 93; cross 81, 95) |
| `nmKept` curve / building / target / noJoin / noNode | 454 / 268 / 228 / 200 / 183 | 455 / 461 / 170 / 93 / 36 |
| `nmKept` chance / inc / slope / forest / road / budget | 86 / 98 / 46 / 45 / 6 / 3 | 86 / 71 / 35 / 18 / 22 / 24 |
| new reasons | - | cut 6, near 5, cross 1 |
| plans with `nmKept=budget` | 1 | 7 |
| PLAN `us=` median / p90 / max | 48.0 / 224 / 462 ms | 42.1 / 193 / 398 ms |
| REFUSED / `nm:` refusals / FAILED | 0 / 0 / 1 | 0 / 0 / 3 (none with a join) |
| SEND `preCost` median join / other (per edge) | 38306 / 32156 (5768 / 9281) | 24190 / 27805 (6246 / 7019) |
| CHECK buildings fell after a build: join / other | 6 of 17 (-11) / 44 of 145 (-155) | 12 of 31 (-42) / 31 of 129 (-186) |
| dead ends on the 16 towns (per km, median) | 305 (1.55) | 331 (1.61) |

1. **More joins: pass on the count, partly on the reasons.** 1.7x the joins (34 vs 20; offline 1.8x), 32 of 274 plans
   with a join; gaps up to 95 m (a node past 80 m: 4 joins). `noNode` 183 -> 36 and `noJoin` 200 -> 93 fell as
   expected, `building` rose (268 -> 461) and `target` fell (228 -> 170); but `curve` stayed (454 -> 455) and `chance`
   stayed (86 -> 86, more candidates reach the roll). `cut` only 6 (not ~2 per snapshot: the snapshot's `degree` ends
   rarely have a street ahead).
2. **Pair joins appear: barely (1).** One `pair:64`: Watersmeet 00:26:15, its first plan (5-edge build, both stubs
   fresh: snapshot `retired` 0 there). Retired joins can't be read from the log (no token marks a join that closes a
   retired stub): the snapshots' `retired:` summed 298 -> 274, and only one join build lowered its town's count
   (Dovemouth `cross:95`, 1 -> 0). Not zoomed (no close-up shot).
3. **No refusals, no assert: pass.** All 32 join builds `BUILT ok=true` (10 at a 3-way: `cross`, the 4-way case),
   0 REFUSED, no `nm:` key refused, no Construction Not Possible, no assert, no crash (the game ran on into a second
   load). The 3 FAILED builds (`ok=false msgs=` empty: Holtbottom 00:26:18 a frame of 7 edges, Two Waters 00:26:57
   6 edges, Lower Arunmouth 00:27:26 1 edge) had no join (`nmJoins=-`).
4. **Looks: not judged at join level; no houses lost: pass.** The 1800 m tour shots can't pick out a join, a 45 deg
   corner or a 90 m join; full-resolution crops (Watersmeet, Dalemere, Seachurch Cove, Seven Oaks) show smooth closed
   loops and no visible kink, no street over water or across a town gap. Buildings: 12 of 31 join builds fell (-42),
   but -24 of that is one Lower Arunmouth `tee:38` build (1 edge, `preCost` 4204: no house in its way) whose next CHECK
   came 6 s later, after SIMGROW years 36-39 and a LEVELS read; without it -18 over 30, about the other builds' rate
   (-1.44 per build). Big join-build pre-costs come from the other pieces of the same proposal: Dovemouth `cross:95`
   4.03 M (9 edges, forest steering, buildings 602 -> 701 after), Seachurch Cove `cross:49` 1.72 M (9 edges).
5. **Frame time: pass, budget less rare.** Plan time lower than the last run; `nmKept=budget` on 7 plans (24 dead
   ends), all late (years ~33-40) in the big towns (Dovemouth 3x, its last plan `budget:11`, Dalemere, Far Ashworth,
   Holtbottom, Merehythe).
6. **Routing:** not seen (no vehicles).
7. **Side T:** not built; `noNode` 36 left (was 183), so an edge split would now add little.
- **Dead ends did not fall:** 331 vs 305 on the 16 towns, most of it the game's own growth (Holtbottom 10 -> 25,
  Little Dalemere 8 -> 20, Dovemouth 26 -> 36; Wheatden 15 -> 9); 34 joins over 40 years are too few to show in the
  totals against that run-to-run spread.

**Run 2026-10-19 19:49Z (§75 rules)**: 39 joins (4 `pair`, 2 corners, the first 5 closing retired dead ends), all
built, `noJoin` 93 -> 10; the numbers in "Side streets and parallel streets" above.


## Real play (first) (2026-10-14, updated 2026-10-16 for §61-§71; the first test without the dev Simulate)

**The next test (2026-10-16).** After §71 the seed `a` Quick check (Combined test iteration step 20) is optional; this
play-through comes first. "What to watch" lists the checks for everything built since (§61-§71).

Every test so far ran the dev Simulate on seed `a`. This one is normal play: you build transport, the calendar moves,
the game decides when towns grow. It answers what a player will see: frame cost over hours, towns growing with
transport, names, satellites over the years, roundabouts, characters, save / reload and removal. Quit TF3 fully first,
so the new modules load.

### Setup

- Organic Towns with its defaults, except **Debug log: On** for this test. The defaults a new player sees: Act on New
  towns only, Vanilla town street angles Automatic, Starting town size Game size, Streets at industries Game default,
  Town and stop names Landscape names, Town growth By deliveries, Satellite towns On, Strong town characters On, Town
  style Automatic, Town layout Organic, Growth lookahead Medium. New towns get the
  steering lock (`INIT ... lock=steer`).
- **Roundabouts & Interchanges** (`square_roundabouts`) on. **DEV mod** (`square_organic_towns_dev`) off (optional: on
  only for a tour at the end; never Simulate or Quick in this test).
- Other mods as you normally play; note them (the log lists them too).

### Maps

1. **Large map, 25+ towns:** a name list you like (USA gives a contrast to the seed-`a` Europe runs), temperate, start
   **1960** (roundabouts are rare before 1960 and common from 1975; one-way rings need the new-style streets). Write down
   the seed.
2. **Medium European map:** Europe list, temperate or dry, start **1900 or 1920**, so the era runs through organic towns,
   gridded districts from 1910 and the first roundabouts after 1940-1960.

### Play (each map)

1. Start the map and wait for the start phases before building much: `CHARACTER pick`, `NAMES survey`, `NAMES shapes`,
   `NAMES words ... assignMs=`, the `NAMES on=true` summary, then `HEAD done`. Note how long the start felt (any freeze
   right after the map loads: that is the names assign, `assignMs=`).
2. **2-3 hours of normal play**, game speed normal to fast. Connect towns with bus lines inside towns and between
   neighbors, and a few train lines between the bigger towns. Build 4-6 bus stops on purpose: one on a town bridge,
   one on its approach, one beside an industry, the rest ordinary; rename one stop yourself.
3. Serve one Works or district town (when one appears: `WORKS event=created` / `DISTRICT event=created`) with a bus
   line, leave another unserved.
4. About halfway: **save, quit to the main menu, reload**, and keep playing. Then once more later: quit TF3 fully,
   start it, load the save (a fresh Lua state).
5. **Removal check, on a copy:** save as a new name, quit to the main menu, load the copy with Organic Towns disabled
   (the Warning dialog is expected). Play 10-15 minutes. Check: it loads without errors; no `[SQOT]` lines and no Lua
   error naming `organic_towns` in stdout.txt; the mod's streets, roundabouts, bridges, town / stop / river names and
   Works / district towns are all still there; towns keep growing on the game's own; cars still drive the rings one way.
   Then load the original save with the mod on again: `CHARACTER pick ... why=saved`, `NAMES on=false why=done`, growth
   goes on.

### What to watch

- **Stutters and frame time:** note the game time of any stutter you feel. `TICKCOST` (every 5 real minutes, always
  on): `maxUs=` and its `at=` stage, `over16ms=` / `over50ms=` counts, `getMaxUs=` (the saved table's copy every
  frame; should stay well under 1000 as the save grows). Also PLAN `us=` and BUILT `ms=`.
- **Towns grow with transport:** served towns get `BUILT ok=true` lines over the hours; the unserved Works / district
  stays small (`OFFSHOOT event=hold`), the served one grows. No long empty streets ahead of the houses.
- **Names:** made-up names that fit their site and climate, no silly ones (send screenshots of the map with names, and
  any name that reads wrong). Industries named after a town follow it. Rivers and lakes named.
- **Satellites over the years:** `SATPACE ... outcome=found` lines spread over the game years (none in the first
  minutes, at most one at a time), the Works and district towns that follow (`WORKS` / `DISTRICT event=created`;
  street-only satellite villages are retired since §64, `SATELLITE on=false why=retired`), and no burst after a reload.
- **Roundabouts:** `RB event=ring` / `built` / `refused` lines from about 1960 on; ordinary towns rarely, the roundabout
  town (if picked: `CHARACTER pick ... roundabout_town`) often. Cars go round counter-clockwise; screenshot one.
- **Characters:** the `CHARACTER pick picked=` line (1-3 towns, `rings=` says whether the roundabout town could be
  picked); do those towns look distinct after an hour? `DENSIFY event=draw|apply` and `LEVELS` lines as towns grow;
  grown towns build taller buildings, young ones stay low.
- **Bridges:** `BRIDGE` lines; a river town's bridge and its far-bank quarter.
- **Stop names:** each stop you build gets a fitting, unique street name within a second or two (`STOPNAME` lines,
  `bridge=` on the bridge stop, the industry name beside the industry); the stop you renamed keeps your name.
- **Errors:** any `ERROR`, `WARN stage=plan msg=planHang`, `FAILED` or a crash; the last `SEND` line before a crash.

Since the seed `a` runs (§61-§71; details in Combined test iteration steps 10-20):

- **Names (§61):** `NAMES shapes ... evoc= charCue= indCue=`: a few evocative names (Two Waters, Seven Oaks ...),
  character towns carrying their kind (X Cove, Far X, X-in-the-Forest), NAME `ind=` on towns by an industry.
- **Landscape and skeleton (§62-§63):** one `LAND ... cues= to= away=` line per town; towns fill their open side first
  (`to=`). `SKEL ... arms=` per shaped town: arms into open land, wood edges left standing; after a reload `src=saved`.
- **Offshoot towns (§64):** `WORKS` / `DISTRICT ... event=create` spread over the years after a `SATPACE ... outcome=found`;
  `OFFSHOOTS n= quota= towns=...:b<buildings>` rising for the served one, flat for the unserved one; no bare crossing
  out in the fields.
- **Locks and the game's streets (§65-§70):** GLOCK `ok=true` mostly, refusals and `event=backoff` rare, never `off=true`;
  `GLOCK event=refund ... why=paid` per send (the Finances window shows the income); VALVE `kind=tip` opening and
  closing (`why=quota|age|gone`), BUILT `tips= tipRej=`; CHECK `lockMat=<v>:size:age:base` rising as towns grow (young
  under ~0.4, 400+ buildings ~0.7-1), `gameShare=` per town rising with it (STREETS `gameShare=` about 0.35-0.5 once the
  towns are grown), `gameKept=`, `lockShare=`. On screen: no long bare locked spikes, no rakes of parallel dead ends,
  no zig-zag arms (PLAN `spikeTrim= rakeHeld= wiggleHeld= lookRelax=`).
- **Knots and hooks (§70-§71):** PLAN `knotHeld=<n>:<cross>/<parallel>/<loop>` and `hookHeld=<n>:<turn>/<back>`,
  STREETS `knotHeld= hookHeld=`; `knotRelax=true` / `hookRelax=true` rare. On screen: no crossing or overlapping curved
  streets, no small lassos, no curled "P" dead ends. Screenshot any you see with its town name.
- **Woods (§63, §70-§71):** PLAN `forestLot=`; BUILT `steer=forest:n` at the rims facing real woods, BUILT / CHECK
  `smallWood=` where copses no longer lock the rim (towns in a patchwork of small woods, like seed `a`'s Shaw, let the
  game build there too); the big woods next to towns still standing after hours.
- **Town growth by deliveries (§66):** `RCI town= ... aim= move=` lines about monthly for served towns, `RCI summary`
  every 10 minutes; a cargo-served town leans industrial, a passenger-served one residential; nothing torn down.
- **Cost:** `TICKCOST` `maxUs=` and `at=` over the hours with the locks and refunds running (GLOCK sends, PLAN `us=`).
- **Save / reload and removal:** as Play steps 4-5: after each reload the towns keep their lock (`CHECK lockMode=steer`),
  SKEL `src=saved`, no burst of SATPACE / GLOCK lines; the removal copy keeps the locked streets (houses still fill
  them, the game just does not branch off them).

### Lines to send

Just "done" with the map names, seeds, the game years played and the real time of any stutter: the sessions are
archived. The game overwrites stdout.txt at every start, so after each game session (before starting TF3 again) run
`make logs ARGS='--tag ot-real'`. For a quick look:
`grep -E '\[SQOT\] (INIT|ANGLE|SAVE|RUN|CHARACTER pick|NAMES|HEAD|TICKCOST|SATPACE|SATELLITE|WORKS|DISTRICT|OFFSHOOT|RB|BRIDGE|STOPNAME|DENSIFY|LEVELS|FRAME|STUCK|FAILED|REFUSED|ERROR|WARN|LAND|SKEL|STREETS|VALVE|RCI|STALL)' stdout.txt`.
With the dev mod on for a final tour: the ALLTOWN lines.

## Combined test iteration (2026-10-14 evening; NEXT_PHASE_BRIEF 46-71)

One round for everything built since the 1927 run. Quit TF3 fully first, so the new modules load. Debug log On;
"Strong town characters" On; Roundabouts & Interchanges (`square_roundabouts`) enabled. Each run's details are in the
sections below. Say "done" after each run; the main session reads the log.

1. **Ring showcase** ("Strong characters" step 1): Blank Slate, game year 1950 or later (1975+ shows the full rates),
   dev showcase. Is the ring one-way, and do cars drive it counter-clockwise? Take a screenshot from above. Then
   (NEXT_PHASE_BRIEF 56, roundabout variety and organic ring roads):
   - **Sizes:** `RB town=<Roundabout town> event=ring size=<mini|s|m|l> R=` lines with more than one size (mini 17, s
     19 / 24, m 34 / 39, l 49 / 59); `wanted=l` with a smaller `size=` means the room was short. Do the bigger rings
     look right, and do the cars still go round one way?
   - **Pairs:** an `RB ... event=pair kind=street|opposite ok=true size= R=` line and two rings of one size in that
     increment, or `RB event=pairWait` and a later `RB event=pair deferred=true ok=true` (the partner along the same
     street, a few plans on; `why=expired:` when it lapsed). The debug log has the pairs not placed, `ok=false why=`.
     Screenshot the pair. Save and reload while a pair waits: the `pairWait` reservation should still complete.
   - **Ordinary towns:** `RB event=ring ... roundaboutTown=false` lines in other EU / MED towns (rare before 1960,
     at most 4 per town); none in JP dense towns.
   - **Roundabout town's empty land:** no rings with arms into empty land (debug `skip why=emptyArm`), no empty
     rectangular loops or long zig-zag leads beyond the houses (PLAN `emptyLen=` stays low, `housedHeld=` counts the
     pieces held). A refused ring (`RB event=refused`) still sends the plain crossing: the SEND / REFUSED / DIAG lines
     around it, please.
   - **EU organic outer rings:** no big equal circles: the rings wobble and sit at uneven gaps, ring arcs and the ring
     road come only near houses (PLAN `ringHeld=`), no cut-off grid patch at the outer zone's seam. Screenshot from
     above, as img_2 of the 2150 run. (Towns framed in an older save keep their even rings: start a new showcase.)
   - **Next showcase run, roundabout town hubs (NEXT_PHASE_BRIEF 57):** after the 2237 run (3 rings in 18 increments,
     no pairs, empty snaking roads). Look for:
     - `RB town=<Roundabout town> event=hub size= R= gate= street= arms= split= partner= reserved=` lines: about one ring
       every second increment (offline 0.69 a plan EU, 0.57 NA grid), all four sizes over the run (`size=l` at a
       gateway on a main / medium street, `m` on a main street, `s` / `mini` on branches; `fell=` on the `event=ring`
       line says why a larger size did not fit). The town should read as a roundabout town: rings across it, not one.
       Screenshot from above, as img_16 of the 2237 run.
     - Pairs: `RB event=pairWait ... kind=street|opposite` after a hub, then `RB event=pair deferred=true ok=true
       hub=true` a few plans on (twins the same size, along the street or across the town). Screenshot a pair.
     - The NA grid roundabout town (seed `a`, usa list, run 3): `event=hub` lines there too (0 rings in 14 plans before).
     - Empty streets: PLAN `ownEmpty=` now shows on forced increments (it was `-`), `sparseHeld=` counts pieces held among
       nearly empty streets; `emptyLen=` of the roundabout town and Shape cross should stay well below the 2237 run's
       4.8 km / combs (offline 2.4-6.4 km -> 0-1.8 km). No long empty snakes north-east / south-west, no empty combs
       west / south of Shape cross, no long thin empty fingers south-west of EU organic.
     - EU organic (year 2060): no regular rectangle cut into its east side; the town gets more regular outward, in steps
       (STYLE `outer=EU_ORGANIC`, the look zone from 320 m; its core look 0.35).
     - Ordinary towns' pairs: rare (`RB event=pair ... rate=` 0.18 for EU towns now, was 0.14).
   - **After the 2347 run (NEXT_PHASE_BRIEF 57b):** the Roundabout town about one `RB event=hub` a step, spread over
     the town, many with `deadEnd`-style stems (`event=ring ... hub=true`); a mix of sizes with `wanted=` mostly met
     (`fell=-`), some m and l; `RB event=pairWait` after hubs and `RB event=pair deferred=true ok=true` later. PLAN
     `origins=` says where each step's new streets came from and the farthest from houses (send me the lines of any
     empty road you see). A refused ring: its `RB event=refused ... near=` line.
   - **After the 0234 run (NEXT_PHASE_BRIEF 57c):** no ring alone at the town's edge with its arms in empty land; EU
     organic's FRAME lines with fewer links and no empty loop round the town; `RB event=pair deferred=true ok=true`
     for most `pairWait` lines.
2. **Seed `a`, europe list, temperate, start 1900, "Move the game date" ticked:** Quick 40 years with the tour.
   Before Quick, and again after it, build 4-5 bus stops: one on a town bridge, one on its approach, one beside an
   industry, two ordinary. At the end, save and reload once. This run checks:
   - strong characters and densify ("Strong characters" step 2; with the date moving, levels 3 from 1950);
   - name shapes, layers and quiet names ("Climate-led names" steps 10-12: `NAMES shapes`, NAME `shape= layer=`);
   - created-town names (no repeated endings, no Sands inland, era forms);
   - staggered satellites ("Staggered satellites": the `SATPACE` found lines spread over the years, the summary
     decades; no burst after the reload);
   - held towns ("Held towns": ALLTOWN `bareLen= foreignLen= modLen=` of the Works / district towns, the `OFFSHOOT
     event=hold` lines);
   - bridge stops and stop climate ("Bridge stops": STOPNAME `bridge=1|end|0 bridgeRead=`, `climate=`, `claim=`);
   - the character quota (`CHARACTER pick` stable; `towns=` counts only the map's own towns).
   - (NEXT_PHASE_BRIEF 57, after the 2237 run's load 2: 0 picks, densify 1 of 16) `CHARACTER pick ... picked=2` with two
     kinds (the replay of that map picks harbour_cove at the lake town of 60255 and island_town at 60263); the debug
     CHARACTER town lines list every kind's score (`top=`) and why (`whys=`). DENSIFY `event=draw` p about 0.3 for the
     shore / linear towns (was 0.13-0.16), about a third of the drawn towns on.
3. **Seed `a`, usa list, temperate, start 1960:** Quick 40 years with the tour. Checks the roundabout town (`RB
   event=ring|built`) and the US characters ("Strong characters" step 3), and US name shapes and layers (Junction /
   Heights only on later towns).
4. **Seed `a`, usa list, dry climate, Town style "European organic":** names and style only. Load the map, wait for
   `NAMES shapes`, and tour or look around. No Quick needed. Checks:
   - INIT `regionSource=setting` with EU style weights ("Town style setting");
   - US names with the Spanish area on one side (Agua X, Las X, San X);
   - no marsh or meadow words.
5. **Optional, seed `a`, asia list, tropical:** a short check. `NAMES on=false why=untaggedList`, the game's names kept,
   a mix of styles in the STYLE lines (not mostly JP_DENSE), `CHARACTER towns=16`.
6. **Optional:** "Strong characters" step 4 (setting Off).
7. **LEVELS by maturity (NEXT_PHASE_BRIEF 58), seed `a`, europe list, temperate, start 1950, Quick 40 years** (the
   2347 run's load 3 again; "Move the game date" as then, off). Then compare with run `2026-10-14_2347_sqot-dev` load
   3 on the seed-a page (`compare/2026-10-14_a`, `--add <session>:<load> --label 'Mod <hhmm> LEVELS'`, see "Compare"
   below):
   - ALLTOWN `pb=` and `lvl=a:/w:/c:` per town against the 2347 table (NEXT_PHASE_BRIEF 58): no town of 600+
     buildings at `a:100/0/0/0` or `w:100/0/0/0`; the grown towns (Mytham, Dart Head, Lower Aberarun, Abercoed,
     Oakhaven) at `c:-` (the engine's weights) or a densify row, pb toward 4-5 (offline 4.9; real buildings lag the
     target, so expect 3.5-4.5 by year 40); the 600-700 building towns (Edton, Padfield, Trefach) on a blend row
     (`c:1/0.571/...` or `c:1/0.727/...`), pb 3.5-4; the small towns unchanged (young: their `c:` as the engine
     left it).
   - `LEVELS town= action=set|clear phase=young|blend|mature|densify why= owner=fill|ours|none tilt=<from>-><to> era=3
     from= to=` lines: `owner=fill` on the towns whose weights the FILL restores wrote, `owner=player` never on this
     map (no one edits the towns); the tilt rising over the years (-1 / -0.75 ... 0, a densify town above 0).
   - `LEVELS ... event=refill` after FILL restores of towns past the young phase: the restore's own weights replaced at
     once (inferred from 2347: every custom weight there followed a restore). If `LEVELS read ... changed=` still
     shows managed towns drifting to `0.0x/...` rows between checks, send those lines.
   - `DENSIFY event=draw` lines during the Quick run now (2347: none until it stopped; the dev Simulate's pool drivers
     read no frame): about 8 of the 13 ordinary towns drawn by year 28, a third of those on; `DENSIFY event=apply` and
     their `LEVELS ... phase=densify` rows.
8. **Forest era and the stall fix (NEXT_PHASE_BRIEF 59).** Three short checks:
   - **Forest era:** seed `a`, europe list, temperate. Load it once at start 1900 and once at start 1950 (no Quick
     needed; wait for every town's STYLE line). Count STYLE `forest=<cover>:hug|clear|deep` per load. The offline
     replay of those towns: 1900 11 hug / 4 clear / 1 deep (was 9 / 6 / 1); 1950 4 hug / 11 clear / 1 deep (was
     3 / 13 / 0; Milton-under-Edge, 60270, goes deep, p 0.95 vs its draw 0.94). The new `forestWhy=p=..(s,e,t,c),u=..`
     field shows each town's draw: the era factor `e` should read 1.12 at 1900 and 1.00 at 1950. In a 1900 hug town,
     look for streets weaving between the woods with some houses still in the trees (not a full clearing).
   - **Stall:** dev showcase, Blank Slate, 2020. EU organic should build its own plans for all its steps: no
     `SHOWCASE STOP ... why=empty_x4` for it. A plan the sparse hold would have emptied shows `sparseRelax=true` on its
     PLAN line with 4 edges at most. Every empty PLAN line now has `held=<hold>=<n>,...` and `emptyRun=`; send any
     `STUCK town=` line (it appears after 6 empty plans in a row, in any game).
   - **Frames:** EU organic's (and any linear / fingers town's) FRAME lines: short links among the game's tips at the
     town's edge are back, but no empty loop running far out round the town (the 0234 run's 35-edge frame).
9. **Literal names (NEXT_PHASE_BRIEF 60):** a new map of seed `a`, europe list, temperate, 1950 (and once usa): `NAMES shapes ... desc= opaque= flavor= multi= rules=s60` (offline about 13 of 16 with a site word, 0-1 opaque, 1-3 flavor, ~8 multi-word: Two Waters, Lower Glavenmouth, Wood Vale, Shinglewater Cove); do the names read like the land, with only a few Aber- / -by / Pen- touches?
10. **Evocative names, character kinds, industry cues (NEXT_PHASE_BRIEF 61):** a new map of seed `a`, europe list,
    temperate, 1950 (and once usa). `NAMES shapes ... rules=s61 evoc= charCue= indCue=`: about 3 of 16 evocative
    names (Two Waters, Watersmeet, Ashgrove, Seven Oaks, Sandy Point ...), `charCue=n/n` (every character town carries
    its kind: X Cove, X Garden City, Far X / X End for the secluded towns, X-in-the-Forest / X Woods for the deep forest
    town, X Sands / X-on-Sea for the coastal hugger), `indCue=` 1-2. NAME lines: `evoc=<gate reading>` on the evocative
    towns (the tag that let it: `confluence:1.00`), `ind=<family>:<m>` on towns with an industry within 1.5 km, `char=`
    the kind. Then: does the deep forest town of the NAME `char=forest` line become the `FOREST ... mode=deep` town
    (`why=...,named`), and no other town deep (`why=names:...`)? Do the names read like the place?
11. **Landscape pull (NEXT_PHASE_BRIEF 62):** the user's run again: usa list, a European build style ("Town style"
    European organic), temperate, start 1900, Quick to about 1940 with the tour (and once seed `a`, europe, 1900, Quick
    40 years, for the compare page). Run `make logs` before restarting the game (the 0440 run's log was lost).
    - One `LAND town= name= cues=open:S,forest:NE,steep:W,water:E k= kRaw= A= to= away= r0= forest= why= shape=
      lobes=` line per town at its first plan (another when its forest read or extent changes it). `to=` is the favoured
      heading (degrees, 0 = east, 90 = north), `away=` the least favoured; `k=` 0 on even land (no lean), up to 0.35
      with woods / hills / water on one side and open land on the other (character towns at most half, `why=char`;
      clear-mode towns feel the woods at half, `why=clear`).
    - PLAN `land=<cues>/k<k>/to<deg>` on every plan (debug).
    - The screenshots against the user's arrows (HISTORY.md 2026-10-15): Oakport, Lower Deer Forks and Buffalo Prairie
      should fill their open land to the south first (`LAND ... to=` around 270, `cues=open:S`), Lower Deer Forks and
      Buffalo Prairie grow less into the woods to the north / east (`forest:N` / `forest:NE`), Twin Rivers' south-east
      fringe less into the trees, Lake Stone on along its river (`water:` with `to=` along the bank). The towns should
      still differ (not all one-sided wedges): the seeded sectors keep about 80 % of their weight.
    - Hilltop towns (`why=char`) still climb; a waterfront / harbour cove keeps its shore (no water cue).
    - Company towns (§61 fix): the debug CHARACTER town lines now say `company_town=heavy:<m>` / `medium:<m>` (or
      `far:` / `steep:`) for towns with a works within 1.5 km instead of `noIndustry` everywhere. A pick is still rare
      (the archived runs' industries sit 1200-1800 m out).
    Lines to send: the LAND lines, the screenshots of the five towns, any town that grew the "wrong" way with its LAND
    line.
12. **Landscape-aware skeleton (NEXT_PHASE_BRIEF 63):** seed `a`, europe names, EU organic, start 1900, Quick 40
    years with the tour (as run `2026-10-15_0539_sqot`, for the compare page). Run `make logs` before restarting.
    - One `SKEL town= name= shape= src=new mode=forest arms=<deg>:<act>:<run>:<clear>:k<x>[:from<deg>][:max<m>]/...
      dropped= minClear= boxed= why= hot= clearM=65 r0=` line per shaped town (linear / ridge / cross / fingers) at its
      first plan. `act`: `keep` / `long` (open all the way, `k` > 1: reaches further), `bend` (`from<deg>`: turned off
      the woods onto another spoke), `short` (`max<m>`: stops 65 m short of the woods), `boxed` (no open heading: as
      before, `why=noAlternative`; character towns `intent`). `dropped=<deg>:wood:<run>` for arms with under 200 m of
      open land. `minClear=` 65 or more. Deep forest towns: `mode=deep`, arms unchanged. Unshaped towns log SKEL only
      when a hotspot moved (`hot=1/3`).
    - After a reload of the save: `src=saved` with the same `arms=` headings; a save from before this build `src=old`.
    - Look: the arms run into open land first, the head start's streets go out further on the open side; after 40
      years the wood edges next to Far Ashworth (W), Norfield (S), Shaw (NW), Little Dalemere (NE) and Two Waters (SE)
      should still stand (compare the 0539 tour shots), the open sides fuller. The towns should still differ.
    - LAND cues: no town names the same compass point for `open:` and `forest:` (Seachurch Cove read `open:N,forest:N`).
    - Satellites: since §64 no SATELLITE seed lines (step 13); the offshoot towns' sites read the woods instead.
    - PLAN `forestCut=` per plan and the buildings at year 40 against 0539 (forestCut mean 0.20, 10661 buildings).
    Lines to send: the SKEL lines, the tour, any town whose arm still runs along a wood edge with its SKEL line.

13. **Named offshoot towns (NEXT_PHASE_BRIEF 64):** the same run as step 12 (seed `a`, europe names, EU organic, 1900,
    Quick 40 years with the tour); one run covers both. Run `make logs` before restarting.
    - No street satellites: no `SATELLITE ... kind=seed` line and no bare X / T crossing out in the fields (0539 had
      five, e.g. 1.2 km NE of Two Waters at -873:917). Debug: one `SATELLITE town= on=false why=retired` per town at its first demand build.
    - Two to four named offshoot towns on the 16 towns: `WORKS ... event=create works=<name>` / `DISTRICT ...
      event=create district=<name>` lines with `why=seeded` or `why=quota`, each right after a `SATPACE ...
      kind=works|district outcome=found` of the same town, then `event=created` (the town found by name) and later
      `event=linked`. `simYear=` on the create lines: staggered (no two in one build round; the offline model founds
      the first at simulated year ~8, the last ~28). The towns that read `why=rare` for both in 0539 (Wheatden, Lower
      Arunmouth, Seven Oaks, Shaw) now draw again (another draw): some of them may found one.
    - The quota: while fewer than 2 are founded, a town of 400+ the draw passed over logs `quotaWait=true` (debug WORKS
      / DISTRICT `on=false why=rare quota=0/2-4`) and later founds one with `why=quota`. After 4 no more (`quota=4/2-4`).
    - Sites: `land=wood<0..1>:clear<m>:lean<-1..1>` on the create lines: wood low (open surroundings), lean mostly
      positive (the town's open side, its LAND `to=`), `forest=` under 0.2 as before. District kinds now include
      `kind=cross` (by a country crossroads: "<Town> Cross" / "<Town> End") and `kind=open` (plain fields: the generic,
      size and compass forms, e.g. "North <Town>").
    - Houses filling: `OFFSHOOTS n= quota= towns=<id>:<name>:works|district:<parent>:y<founded>:b<buildings>/...` once per
      Simulate round (and every 5 real minutes): each town's `b` should rise from its first fill (~60-80 buildings for a
      district, as Aberdart Grange in run 1927) over the rounds; one that stays flat while its parent grows is the
      thing to report (offshoot towns grow by the game's own demand, which wants transport).
    - On the tour: each offshoot town is a small separate place with its own name label and houses, linked to its
      parent by a road; none sits inside or against a wood.
    - Old save (optional): load a save from before this build with a street satellite: it is still there and grows
      (`SATELLITE ... kind=grow`), its Works / districts are kept.
    Lines to send: the WORKS / DISTRICT create lines, the OFFSHOOTS lines (or the session name) and the tour shots of
    the offshoot towns.

14. **Lock every mod-built street (NEXT_PHASE_BRIEF 65):** two runs; `make logs` between them.
    - (a) **Real map:** seed `a`, europe names, EU organic, start 1900, Quick 40 years with the tour (as 0629). Check:
      - `INIT ... lock=mod lockLegacy=shape`; every `BUILT` line `lockMode=mod` with `locked=` equal to `edges=`.
      - `STREETS towns= edges= modEdges= gameEdges= coreEdges= gameShare= stalled= stallFires= lockMod= lockLegacy=`
        every 10 real minutes: `gameShare` is the game's share of the new streets. 0629 had ~2/3 (16 towns, ~706 ->
        ~3880 edges, ~1100 of them ours). Lower is the aim; if it stays near 0.6 the game is branching off its own
        new streets (the core's children are unlocked), which is the thing to report.
      - Forest: the PLAN `forestLot=` sum over the run vs 0629's 50.3 ha, `forestHeld` vs 238 / 278 plans; on the tour,
        do the woods around the towns stay (the game's streets were the ones running into them).
      - Stalls: `STALL town= event=fire level=1..3 streak= capRatio= applied=` lines (capped at 12 per town and
        session: `event=capped`). A few per town is fine; many towns stalled for long (`stalled=` on STREETS above 3,
        CHECK `stallStreak=` climbing) means the supply is short. `level=3` (the forest hold a step looser) should be
        rare. Buildings at year 40 vs 0629's 11107: much lower would mean the lock starves the towns.
      - Look: towns still grow out from their cores, our streets get houses (CHECK `ownOpen` not piling up), no long
        empty streets.
    - (b) **Showcase A/B** (dev, Blank Slate, "Showcase: build all", 20 steps): the EU organic town and Shape: linear
      run the new lock, their twins "EU organic (old lock)" / "Shape: linear (old lock)" the old one, "Shape: linear
      (plain)" none. Compare the pairs' `SHOWCASE LOCK ... when=report` lines: `lockUsed=mod|shape|off`, `gameEdges=`
      and `gameShare=` (the game's streets since the first step), `attached=` (game side streets on ours: 0 with the new
      lock), `buildings=`, `cap=` / `capRatio=`. Expect fewer game edges and about the same buildings with the new
      lock; on the tour, the shape of the pairs side by side.
    - Old save (optional): a save from before this build keeps its towns on the old lock (`CHECK ... lockMode=legacy`,
      `BUILT ... lockMode=shape`); a town the mod first builds in after the load gets `lockMode=mod`.
    - Console check of the lock on one town's streets (in game, the key below Esc; town id from a CHECK line):
      `local CT=api.type.ComponentType; local n,l=0,0; for _,e in ipairs(api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(X,Y),600,CT.BASE_EDGE)) do local c=api.engine.getComponent(e,CT.BASE_EDGE); if c and api.engine.getComponent(e,CT.BASE_EDGE_STREET) then n=n+1; if c.roadDevelopmentLocked then l=l+1 end end end; print("[LOCKCHK]",n,l)`
      (X, Y = the town's centre, e.g. a SNAPSHOT / CHECK town's position; prints street edges and locked ones within
      600 m: locked should be about CHECK `modEdges=`, the rest the core and the game's streets).
    Lines to send: the STREETS lines, the STALL lines, the session names.
15. **Town growth: By deliveries (NEXT_PHASE_BRIEF 66; PLAN.md 6.2 "Supply-driven district weighting").** Real play,
    no dev Simulate (it makes no deliveries, so the weighting leaves its towns alone). Two saves of one new map
    (any list, temperate, start 1950, 8+ towns), Debug log On:
    - (a) **By deliveries** (the default; INIT `townGrowth=deliveries`). Pick two towns of similar size away from
      each other. Town A: industrial cargo only (a truck or rail line delivering the goods its industrial buildings
      ask for, e.g. from a nearby factory), no passenger line. Town B: passengers only (a bus line inside the town and
      one to a neighbour), no cargo. Play about 10 game years.
    - (b) **Game default:** the same map from its first save, `town_growth=2`, the same lines, the same 10 years.
    - Check in (a): `RCI town=<A> ... r/c/i=..->..` lines about once a game month while A grows, `aim=12/12/76` (or
      near) for A and `aim=76/12/12`-ish for B, `sum=N->N` (the initial sum kept; above it only by the 5 % ceiling),
      `move=` at most 0.030. `RCI summary` every 10 minutes: `weighted=` towns, `lean=` counts. After 10 years A's
      ALLTOWN / inspector `rci=` share should read clearly industrial (60 %+ is the aim, base towns stay under ~45 %)
      and B residential; (b) should stay near the base spread (findings towns.md "Measured spread").
    - The total: town sizes (ALLTOWN `capacity=`, the town window's population) in (a) vs (b) within ~5-10 %: the mix
      moves, not the speed.
    - Nothing torn down: A's residential / commercial building count never drops when the weighting lowers them (the
      weighting never sets a district's target below what is built; whether a lowered target ever demolishes is the
      open question).
    - Level weights: `RCI town= levels=putBack` lines (the engine rewrote a town's level weights with the write) and
      LEVELS `event=refill`; a town's buildings should not get stuck at level 1 (pb in ALLTOWN as before).
    - The look: A's Works / lane draws (`WORKS ... on=`), B's districts; a commercial-heavy town's upward doses
      (`UPWARD why=densify`).
    - Save, reload: the RCI lines continue (`n=` counts on from the saved `k`), no jump in `r/c/i`.
    - Console check of the supply read (in game, key below Esc), one line per town:
      `local tu=ug_require("::/game_mechanics/towns/town_util.tl"); for t in pairs(api.engine.system.townBuildingSystem.getTown2personCapacitiesMap()) do local sd=tu.getCargoSupplyDemands(t); local function s(l) local a,b=0,0 for _,c in ipairs(l or {}) do a=a+c.supply b=b+c.demand end return a.."/"..b end; local n=api.engine.getComponent(t,api.type.ComponentType.NAME); print("[RCIS]", n and n.name, api.engine.util.town.getTownLineUsage(t), s(sd.residential), s(sd.commercial), s(sd.industrial)) end`
      (prints line use and supply / demand per land use; A should show industrial supply, B line use).
    Lines to send: the RCI and RCI summary lines, the `[RCIS]` lines, both session names.
16. **Game streets locked, valves (NEXT_PHASE_BRIEF 67; PLAN.md 6.2 "Game-street locking and valves").** First the
    console probe on a throwaway save (it rebuilds one street and costs money), then the run.
    - (a) **Console probe: do houses survive a rebuild?** Any save with a town; point the camera at a town street with
      houses, open the console (the key below Esc) and paste:
      `local E=ug_require("square_organic_towns::/organic_towns/ot_engine.lua"); local c=api.gui.camera.getCameraData(); local t=E.closestTown(c.x,c.y); local _,bb=E.townBuildings(t,E.town2buildings()); local id,bd=nil,1e12; for _,ed in ipairs(E.streets(c.x,c.y,250)) do local d=((ed.p0[1]+ed.p1[1])/2-c.x)^2+((ed.p0[2]+ed.p1[2])/2-c.y)^2; if (bb[ed.id] or 0)>0 and not ed.locked and not ed.owned and ed.objects==0 and not ed.inConstruction and ed.etype=="normal" and d<bd then id,bd=ed.id,d end end; if not id then print("[GLPROBE] none: no housed unlocked street within 250 m") else local p,l=E.lockProposal({id}); local ctx=E.context(true); local pre=E.precheck(p,ctx); print("[GLPROBE] before town="..tostring(t).." edge="..id.." houses="..bb[id].." townBuildings="..#(E.town2buildings()[t] or {}).." preOk="..tostring(pre.ok).." preBuildings="..tostring(pre.buildings).." preCost="..tostring(pre.cost).." msgs="..table.concat(pre.msgs,"|")); if pre.ok then E.sendBuild(p,ctx,function(ok,info) local nid,lk=E.edgeBetween(l[1].n0,l[1].n1,id); local _,b2=E.townBuildings(t,E.town2buildings()); local pm=E.parcelMap(); print("[GLPROBE] after ok="..tostring(ok).." new="..tostring(nid).." locked="..tostring(lk).." houses="..tostring(nid and b2[nid] or "-").." parcels="..tostring(nid and pm and pm[nid] and E.parcelCount(pm[nid]) or "-").." townBuildings="..#(E.town2buildings()[t] or {}).." cost="..tostring(info.cost)) end) end end`
      It picks the housed, unlocked town street nearest the camera centre (within 250 m), prints `[GLPROBE] before`
      (its houses, the town's buildings, the pre-check: `preBuildings=` > 0 means the rebuild would remove houses, and
      then nothing is sent), rebuilds it locked when the pre-check passes and prints `[GLPROBE] after` (the new edge,
      `locked=`, its houses and parcels right after, the town's buildings, the cost). About 10 s later, with the camera
      still there, paste the follow-up (every locked street near the camera with its houses now):
      `local E=ug_require("square_organic_towns::/organic_towns/ot_engine.lua"); local c=api.gui.camera.getCameraData(); local t=E.closestTown(c.x,c.y); local _,b=E.townBuildings(t,E.town2buildings()); local pm=E.parcelMap(); for _,ed in ipairs(E.streets(c.x,c.y,250)) do if ed.locked then print("[GLPROBE] later edge="..ed.id.." houses="..(b[ed.id] or 0).." parcels="..tostring(pm and pm[ed.id] and E.parcelCount(pm[ed.id]) or "-")) end end`
      I read the lines with `make logs-grep PAT='GLPROBE' ARGS='--session live'`. Houses kept (the `after` / `later`
      count equals `before`, the town's buildings unchanged, a cost about a street's price): `WITH_HOUSES` and the
      housed core can be turned on. Houses gone or a big cost: they stay off.
      **Done 2026-10-15** (session `2026-10-15_1936_sqot-glprobe`): 6 houses / 22 lots kept, cost 1650, town 318
      buildings before and after; `WITH_HOUSES` is now on.
    - (b) **Run:** seed `a`, europe names, EU organic, start 1900, Quick 40 years with the tour (as 0629 / 0759). Check:
      - `INIT ... lock=mod`; GLOCK lines: `ok=true` for most, `kind=game|core`; refusals (`ok=false why=precheck|
        buildings|cost|failed`) few, and `GLOCK event=backoff` rare (`off=true` should not appear).
      - The game's share of the new streets (STREETS / CHECK `gameShare=`) vs 0759's 0.58 (1704 game / 1231 mod; per
        town 0.35-0.81). Note: the share counts the game's streets whoever locked them; the aim is fewer of them, and
        CHECK `gameOpen=` (unlocked game / core edges) staying low while `glocked=` grows.
      - VALVE lines: `event=open heading= dir= why=land|arm|open` per town, then `event=close why=quota|age|gone` and a
        new heading (rotation). Compare the open headings with the town's LAND `to=` / SKEL arms: they should agree,
        never into the woods (LAND `cues=forest:`), water or toward a neighbour. `event=want` (no anchor: a stub
        follows, `kind=stub`) should be the exception.
      - Forest: PLAN `forestLot=` sum vs 0759's 46.9 ha (0629: 50.3); buildings at year 40 vs 0759's 10480 (much lower:
        the towns starve); STALL lines (with `valveExtra=`) few, `stalled=` on STREETS at most ~3.
      - Look on the tour: the game's own organic fill sits around the valves' headings, the rest of the town grows on
        our streets; no orphaned junctions (red dead-end signs) at locked game streets; no traffic stuck at them.
    Lines to send: the `[GLPROBE]` lines, the STREETS, VALVE and STALL lines, a count of GLOCK `ok=false`, the session
    names.
17. **Small follow-ups (NEXT_PHASE_BRIEF 68; PLAN.md 6.2 "Small follow-ups (§68)").** Can share step 16's run (b).
    - (a) **Quick moves the calendar by default:** open OT Dev's Simulate tab before Quick: "Move the game date with the
      simulated years" is ticked. Quick: `SIMGROW start ... moveDate=true`, then `SIMGROW date year= was= ok=true` at
      the build rounds, the year climbing 1900 -> 1940 (forward only). Era effects to compare with 0759 (calendar
      stuck): level 3 buildings from 1950 do not appear (1940 is the end), so the comparison is the forest odds (FOREST
      / PLAN `forestMode=`) and `SATPACE` slots (`years=` now above 0: the offshoots may come a little sooner). On a
      1950 map Quick reaches 1990: level 4 buildings toward the end.
    - (b) **Refund of the lock rebuilds:** one `GLOCK event=refund amount= why=paid paid= cost=` per `GLOCK event=send`
      that built; `paid` about `cost`; the Finances window's street construction line shows the income. `why=mismatch` now and then is fine (other spending in the same
      frames); `why=notCharged` on every line means the callback's balance does not show the charge yet (send it).
      STREETS `glockRefund=` sums them. With infinite money: no refund lines.
    - (c) **Company towns:** on a map with a heavy works (steel mill, refinery, saw mill, brickworks, coal or iron mine,
      quarry, oil well) about 1-1.7 km from a flat starting town: `CHARACTER town= event=pick kind=company_town` with
      `why=heavy:<m>`, the town a strict grid toward the works. On seed `a` none is expected (only farms, fishing and
      logging near its towns: `company_town=noIndustry|light`). Send the CHARACTER pick lines of any new map.
    - (d) **Old save:** load a save from before this build (e.g. the 0759 save): the debug STYLE lines say `draws=1` for
      its towns (the old draws kept), towns founded later `draws=2`; the existing towns' forest modes (`forestMode=` on
      PLAN lines) match the earlier session's.
    Lines to send: the SIMGROW start / date lines, the GLOCK refund lines (or their count by `why=`), the CHARACTER
    pick lines, a few STYLE lines from the old save.

18. **Steering lock (NEXT_PHASE_BRIEF 69; PLAN.md 6.2 "Steering lock policy (§69)").** Seed `a`, europe names, EU
    organic, start 1900, Quick 40 years with the tour, the calendar moving (as 1936). A new map: every town gets the
    steer lock (`INIT ... lock=steer`, CHECK `lockMode=steer`; a save from 0759 / 1936 keeps `mod`).
    - **Game share:** STREETS / CHECK `gameShare=` about **0.35-0.5** (1936: 0.22, 0759: 0.58). CHECK `lockShare=`
      (the town's lot edges locked) high in young towns (`lockMat=` < 0.3: ~0.9+) and falling as they grow (grown
      towns ~0.5-0.7); `gameKept=<inside>/<open rim>` the game streets the lock leaves open.
    - **Forest:** PLAN `forestLot=` sum **at most 1936's 34.7 ha**; BUILT `steer=forest:n/...` and GLOCK `kind=game`
      lines at the rim toward the woods.
    - **Tips:** BUILT `tips=` and `tipRej=` (forest / water / neighbour / inner / sep), VALVE `event=open kind=tip`, then
      `event=close why=quota|age|gone`. On the tour the game's own fill should start at those tips, out into open land.
    - **No bare spikes:** PLAN `leadCap=` (150-250), `spikeTrim=<lead held>/<arms trimmed>`; on the tour no long locked
      street without houses (Shaw's V south-west, Seven Oaks' two southern roads, Merehythe's bridge to the north
      peninsula in 1936). BRIDGE `target=houses|industry|town|short len=` on a plan, `why=noTarget noTarget=<n>` for the
      refused empty crossings.
    - **No rakes / zig-zags:** PLAN `rakeHeld= rakeJoin= wiggleHeld= lookRelax=`; Seven Oaks' south side without the
      comb of parallel dead ends, its east arm without the zig-zag.
    - **Texture:** inside the towns more of the game's own irregular side streets than in 1936 (the old runs' look),
      the arms and edges still ours.
    - Buildings at year 40 about 1936's 9709 (98 % capacity); STALL lines few.
    Then the comparison page: `uv run plans/square_organic_towns/compare/build_compare.py --out plans/square_organic_towns/compare/2026-10-15_a-lock
    --add <session>:<load> --label 'seed a 1900 Quick 40 (§69)' --dir mod-69 --shot-px 1600 --shot-q 50`.
    Lines to send: STREETS lines, the session name and load; I read the rest from the log.
19. **Maturity sooner, no knots (NEXT_PHASE_BRIEF 70; PLAN.md 6.2 "Steering lock policy (§69)", "§70").** As step 18
    (seed `a`, europe names, EU organic, 1900, Quick 40 with the tour, the calendar moving), a new map.
    - **Maturity:** CHECK `lockMat=<v>:size<a>:age<b>:base<c>`: the mid-size towns (300-550 buildings: Holtbottom,
      Dalemere, Shaw, Little Dalemere, Norfield; 2031: lockMat 0-0.16) read about 0.55-1 by year 40 (size / age), small
      or young towns stay low (year 10-20: under ~0.4). `age` is 0 for a town framed before §70 (no `fy`).
    - **Game share:** STREETS / CHECK `gameShare=` about **0.35-0.5** (2031: 0.24); per town the mid-size towns now
      ~0.3-0.6 (2031: 0.00-0.34). **forestLot** sum at most ~34 ha (2031: 32.2); BUILT `steer=forest:n` still at the
      rims facing woods.
    - **Knots:** PLAN `knotHeld=<n>:<cross>/<parallel>/<loop> knotRelax=`; STREETS `knotHeld=`. On the tour Merehythe's
      south (2031: crossing / overlapping curved locked streets) without crossings away from junctions, curves running
      beside each other or small lassos. `knotRelax=true` should be rare.
    - **Clearings:** Two Waters' south (2031: growth into the clearings between woods): BUILT `steer=forest:n` there and
      `tipRej=corridor:n`; no new streets down the clearings.
    - Buildings at year 40 about 2031's 9215 (98 % capacity); no STALL lines.
    Then the comparison page: `uv run plans/square_organic_towns/compare/build_compare.py --out plans/square_organic_towns/compare/2026-10-15_a-lock
    --add <session>:<load> --label '<hhmm>: maturity + knots (§70)' --dir mod-70 --shot-px 1600 --shot-q 50`.
    Lines to send: STREETS lines, the session name and load; I read the rest from the log.
    **Done 2026-10-16** (session `2026-10-16_0405_sqot`, HISTORY.md): game share 0.32, forestLot 35.8 ha, knots gone;
    Shaw / Dalemere / Little Dalemere still low (small woods), a few curled hooks: step 20.
20. **Small woods, no hooks (NEXT_PHASE_BRIEF 71; PLAN.md 6.2 "Steering lock policy (§69)", "§71"). Optional: the real
    play-through ("Real play (first)") comes first.** As step 19 (seed `a`, europe names, EU organic, 1900, Quick 40
    with the tour, the calendar moving), a new map.
    - **Small woods:** BUILT / CHECK `smallWood=` > 0 in Shaw (a patchwork of small woods), Dalemere, Little Dalemere;
      their CHECK `gameShare=` up from 0.07 / 0.12 / 0.15 (0405); STREETS `gameShare=` toward 0.35-0.5 (0405: 0.32).
      PLAN `forestLot=` sum within ~36 ha (0405: 35.8); the big woods still lock (`steer=forest:n`).
    - **Hooks:** PLAN `hookHeld=<n>:<turn>/<back> hookRelax=`, STREETS `hookHeld=`; on the tour no small curled "P" dead
      ends in Merehythe and Shaw (0405 had a few; Shaw's NE hook).
    - Buildings at year 40 about 0405's 9079; no new STALL lines.
    Then the comparison page: `uv run plans/square_organic_towns/compare/build_compare.py --out plans/square_organic_towns/compare/2026-10-15_a-lock
    --add <session>:<load> --label '<hhmm>: small woods + hooks (§71)' --dir mod-71 --shot-px 1600 --shot-q 50`.

After the runs I add each one to its comparison page (`compare/2026-10-14_a`, `_a-usa`) and write up the results.

## Strong characters (2026-10-14; NEXT_PHASE_BRIEF 54; PLAN.md 6.3 "Strong characters, roundabout town, densify")

Strong town characters (1-3 towns per map with a striking site and a kind that pushes the planner hard), the
roundabout town's one-way rings, and the densify trait. The setting "Strong town characters" is On by default for
this run. Enable Roundabouts & Interchanges (`square_roundabouts`) for steps 1 and 3: without it no roundabout town is
picked (`CHARACTER pick ... rings=no:noMod`). Debug log On (CHARACTER town lines of the unpicked towns, RB skips).

### 1. The one-way ring first (dev showcase, Blank Slate, a game year 1950 or later)
1. Start the showcase with Roundabouts & Interchanges on. The layout has two roundabout towns: "EU ext roundabout"
   (the dev probe's ring at a dead end) and "Roundabout town" (`RB_TOWN`: the main mod's planner, kind
   roundabout_town).
2. After a few rounds, look for `RB town=<Roundabout town> event=ring ring=S:R=24:arms=4 ... oneway=true`, then `RB ...
   event=built rings= total=`, and no `RB event=refused` (if there is one: send it, and the SEND / REFUSED lines around
   it). No crash: every ring node has a config (`SEND ... cfgAdd=`).
3. In game, at the Roundabout town: is the ring a one-way street (the street tool's one-way arrows, or the street's
   info)? Do the cars drive it counter-clockwise only and leave by the arms? Does the town hang streets on the ring
   (it should not: the ring is locked) or line it with houses? A screenshot from above.
4. "Roundabout here" (dev Town tab) is the dead-end probe as before.

### 2. European map, seed `a`, "Move the game date" ticked
1. New map, seed text `a`, the europe list, temperate, Landscape names, 16+ towns; dev Simulate Quick 40 years with
   "Move the game date" on (the calendar follows, so level 3 exists from 1950).
2. At the start (before the HEAD start line): `CHARACTER pick on=true towns= count= picked= kinds=<kind>:<town>,...`
   and one `CHARACTER town= event=pick kind=` line per picked town. Expect 1 below 10 own towns, 2 from ~12, 3 from ~20;
   no kind twice; picks at least 3 km apart. The roundabout town is picked only on maps starting from 1950 (France
   1940; outside Europe 1955).
3. Each picked town: `CHARACTER ... event=apply applied=yes style= form= shape= block= motifs=`, STYLE / PLAN `char=`.
4. Tour the picked towns (dev "Tour all towns", ALLTOWN `char=`); what each kind should look like:
   hilltop: a compact dense knot on the summit, winding small streets, no sprawl down the slope; clifftop: a shallow
   strip along the cliff edge with a promenade, nothing below; harbour cove: tight small blocks round the bay, dense at
   the water; waterfront: streets with the river, a bridge early; street village: one long main street with houses on
   both sides, almost no side streets; company town: a strict grid of long terraced rows pointing at the works; garden
   city: radial boulevards and rings, big blocks, green wedges; island town: covering its island, a ring road along the
   shore.
5. Densify: `DENSIFY town= event=draw on= why=p=..,u=..` once a town reads mature (about a third on), then `DENSIFY ...
   event=apply core= levels= pb=` and LEVELS lines with higher k for those towns; at the end ALLTOWN `pb=` / `lvl=` of
   the densify towns against the others (ALLTOWN `char=densify`).
6. Save, reload: `CHARACTER pick ... src=saved` with the same kinds; the towns keep their look (frames `ck`).

### 3. US map
1. New map on the usa list, a start year of 1960 (roundabouts outside Europe from 1955), flat country if the map
   generator allows; Quick 40 years.
2. As in 2: the picks (company towns by the industries, garden city / roundabout town on open land, waterfront on a
   river), `RB event=ring|built` for the roundabout town, `DENSIFY` lines.

### 4. Setting Off (a short check)
New map with "Strong town characters" Off: `CHARACTER pick on=false why=setting`, no `RB` ring and no `DENSIFY` lines;
deep forest towns still picked as before (`FOREST mode=deep`).

### Lines to send
`grep -E '\[SQOT\] (CHARACTER|RB|DENSIFY|LEVELS)' stdout.txt`, the STYLE / PLAN lines of the picked towns (`char=`),
the dev ALLTOWN lines, and screenshots of each picked town and of the ring.

## Town style setting (2026-10-14; NEXT_PHASE_BRIEF 55; PLAN.md 2.2 "Town style setting")

Checks that the "Town style" setting picks the towns' look apart from the names.

1. Quit TF3 fully. NEW map, **USA** name list, temperate, Organic Towns: Act on **New towns only**, **Town style:
   European organic**, Vanilla town street angles Automatic, Debug log **On**, the rest default.
2. Right after the load: `[SQOT] ANGLE choice=auto region=EU regionSource=setting ... angle=...->35` and
   `[SQOT] INIT on=true ... region=EU regionSource=setting ... params=... style=3 ...`.
3. Towns: STYLE / SITE lines show EU weights (EU_ORGANIC / EU_EXTENSION lead, NA_GRID rare); the towns look European
   organic, not US grids.
4. Names stay American: town and stop names from the US list (Landscape names `gen=usa`), as with Automatic.
5. Optional: the same map with **Town style: North American grid** (`style=2`): `regionSource=nameList`, every town a
   grid, as before this change. And **Mixed** (`style=9`): `region=MIXED`, a broad mix of styles.

## Held towns (2026-10-14; NEXT_PHASE_BRIEF 52 item 3; PLAN.md 6.3 "Held towns")

Checks that the Works / district towns the mod creates keep no big empty street networks. Run `2026-10-14_1927_sqot`
showed 25-33 km of "empty" street there, but it was the parents' engine-built streets. The mod gets no streets into
them while they are held.

1. Quit TF3 fully. NEW map, seed `a` (European list, temperate), Organic Towns default with Debug log **On**; the dev
   mod on. Wait for `HEAD done`.
2. Dev Simulate: **Quick** (40 years, pace 0), Move the game date off; then **Tour all towns**.
3. For every Works / district town (DISTRICT / WORKS `event=created ... works=<id>` / `district=<id>`), check its ALLTOWN line:
   - `bareLen=` (street with no house of any town) stays small: under ~1.5 km for a 40-80-building town. In the
     1927 run its `emptyLen=` read 1-10 km. `emptyLen=` may stay large where the parent's streets reach in: then
     `foreignLen=` holds most of it;
   - `modLen=` doesn't grow past the founding link (~0.5-1 km).
4. `grep 'OFFSHOOT event=hold'`: lines `why=below` for the created towns that needed streets (once per street count).
   `why=guard:...` with `by=<parent>` lines are allowed. No SEND / BUILT with `town=<created id>` while it has fewer
   than 120 buildings.
5. Optional, longer: keep Simulate going (scope near the camera, as in the 1927 run) to ~100+ years. Then re-tour and
   compare the created towns' `bareLen=` / `modLen=` with step 3: they should hardly change.
6. Also check: original towns that still grow get BUILT lines as before. `OFFSHOOT event=hold why=noGrowth` on an
   original town shows only once its size factors stay at 1 and its initial capacity is built (normal play without
   transport, after the head start).

Send: the ALLTOWN lines of the created towns and their parents, every `OFFSHOOT event=hold` line.

## Climate-led names (2026-10-14; NEXT_PHASE_BRIEF 47-49; PLAN.md 6.3 "Plausible, climate-led names", "Satellite and Works name variety")

Checks that Landscape names are made up from region, climate and map (no real list names), that each climate brings its
own words and keeps out the others', that no lake name appears without a lake, that the Asian list keeps the game's
names, and that created towns (Works, districts) vary.

### Setup

- Quit TF3 fully, `make link` (done). Main mod (the dev mod's tour helps for screenshots). Organic Towns: Act on **New
  towns only**, "Town and stop names" **Landscape names**, "Satellite towns" On, Debug log **On**, the rest default.
- Four NEW maps, seed text `a`, the same map settings each time, only the **climate** changes: temperate, tropical,
  dry, subarctic. Name list: Europe (England) for temperate and subarctic, USA for tropical and dry. Then one tropical
  map with the Asian list. Quick 40 years (or play) on each so Works and districts appear.

### Steps

1. **Every map, right after the load**: `[SQOT] NAMES survey ...` first, then 16 `[SQOT] NAME town=... src=generated`
   lines and `[SQOT] NAMES on=true why=ok mode=landscape gen=en|usa ...`. No town keeps or gets a name of the game's list
   (Penkridge, Haslemere, Darley Dale, Lake in the Hills ... are gone).
2. **`[SQOT] NAMES words ... climate=<climate> misfit=...`**: `climate=` matches the map; `misfit=` lists the words the
   climate turned down (`Oak:tropical/oak`, `Marsh:dry/marsh`, `Palm:subarctic/palm`) and the survey corrections
   (`lake:sea` on a map without lakes).
3. **Temperate**: names as before this round (fords, dales, -ton / -ham, no palms, coral, mesas).
4. **Tropical** (USA list): palms, coral, keys / cays, reefs, lagoons, mangroves on several coastal towns; no oak,
   birch, pine, cedar, cottonwood, maple, heath, moor, snow anywhere (towns, rivers, lakes, Works, districts). On the
   island map of run 0814: no "Lake" or "Canyon" name (`lakes=0` in the survey).
5. **Dry** (USA list): mesas, washes, buttes, wells, sage / yucca words where they fit; no marsh, fen, meadow or moss.
6. **Subarctic** (England list): snow, frost, fells, birches; no palms, coral or lagoons.
7. **Asian list, tropical**: `[SQOT] NAMES survey ...` still logged, then `[SQOT] NAMES on=false why=untaggedList
   list=asia`; the towns keep the game's names. Its Works / districts: `[SQOT] WORKS ... event=create works=<a name of the
   Asian list> ... pattern=list`, no "High Wuhan" or "Wenzhou Works".
8. **Created towns** (any map, after Quick 40 years): every `[SQOT] WORKS ... event=create` and `[SQOT] DISTRICT ...
   event=create` line has `pattern=` (parent / company / cue / generic / compass / shore) and `suffix=`; after each a
   `[SQOT] NAMES offshoot used=... n=` line. On the map: "Works" at most once, no suffix twice while others were free;
   Works named by their industry (Glassworks by a glass works, Colliery / Pit / Zeche by a coal mine) or company towns
   ("Crossleyville", "Port Garside"), river / valley compounds ("Ironbridge", "Furnace Vale"); districts with the compass
   or the site ("North X", "Upper X", "X Ford"); Sands / Beach / -on-Sea only on a sandy sea shore, once each.

9. **Stop names, styles and the character quota** (2026-10-14, NEXT_PHASE_BRIEF 48 items 3-4, 49): on each climate
   map build 4-5 bus stops (centre, outskirts, a shore, a forest edge). Each `[SQOT] STOPNAME ... climate=<the map's>
   noLake=true|false misfit=climate:n,lake:n`: tropical stops carry no Oak / Birch / Pine / Maple / Heath words, dry ones
   no Marsh / Fen / Meadow / Moss, subarctic ones no Palm / Lemon / Olive; on the island map (`lakes=0`) no Lake /
   Lakeside / Lakeshore / Mere (`noLake=true`; `lakeFix=noLake|sea` where the town read a lake); a stop on a bridge still
   gets its bridge name. On the Asian tropical map: the `[SQOT] STYLE` lines show a mix (the run had 14 of 16 JP_DENSE;
   expect no style on more than about half the towns, `|ASIA|` in `styleWhy=`), and the debug `[SQOT] CHARACTER towns=16
   created=0 count=2` line keeps `towns=16 count=2` with the same picks after Works / districts appear (`created=1..`).

10. **After the 1729 run's fixes** (2026-10-14, NEXT_PHASE_BRIEF 50; also with the dev Simulate, which ran the 1729
    builds): every `DISTRICT ... event=create` / `WORKS ... event=create` line has a real `pattern=` (generated, parent,
    compass, cue, shore, company ...) and `suffix=` (never `pattern=- suffix=-` / `pattern=generated suffix=-`); no
    "-sands" / "Beach" / "-on-Sea" district by a lake or inland, each beach suffix once per map. Among neighbouring towns
    no first part twice (the run had Myt x3, Spruce x2) and no affix family twice ("-under-" x3, "haven" x2); a river's
    name in at most two town names, one of them a whole-name form ("Port Big Sandy" or "Big Sandy Valley", not both, nor
    "Big Sandy Junction"); no bare "Narrows"; no Gaelic / Welsh mix ("Invercoed") and no "Acbottom". `CHARACTER` keeps
    `towns=16 count=2` with the same picks while `created=` climbs 1 .. 6, also during Simulate.

11. **Name shapes chosen per map** (2026-10-14, NEXT_PHASE_BRIEF 53 Part A; PLAN.md 6.3 "Name shapes chosen per map"):
    one `[SQOT] NAMES shapes quota=... used=... frames= whole= twins= quiet= towns= miss= left=` line per new map, and
    `shape=` on every `NAME town=` line. On a 16-town Europe map: about 11-13 `shape=plain`, at most 1 frame (on an
    ordinary base: "Kirkby-under-Edge", "Sutton-on-Arun", never "Fellhaven-under-Dun"), at most 1 saint, at most 1
    whole name; the run had 11 of 16 framed. A compass word (North / South / East / West X) only on a town 6 km or
    less from a town with the same base, on that side of it ("Thurby" / "South Thurby"), never because the town is in
    the map's south; Upper / Lower on a twin or on a name with its river's stem ("Lower Arunmouth" at the mouth).
    A named river, lake, peak or bay in at most 2 town names; most names one or two words, none of 4. On the USA map:
    1-2 whole names on the strongest cues (Three Rivers / Middle Fork at a real fork), many "Name + Generic" and
    -ville / -burg names. In each half of the map one dialect leads (Norse -by / -thorpe / -dale / -water on the coast
    or east side, Saxon -ton / -ham / -mere in the core, Gaelic Bal- / Kil- / Inver- or Welsh Llan- / Tre- / Pen- on the
    far edge). Saved maps: names unchanged on load (`NAMES on=false why=done`).

12. **Settlement layers and climate shape tables** (2026-10-14, NEXT_PHASE_BRIEF 53 Part B; PLAN.md 6.3 "Name shapes chosen
    per map, Part B"). The four climate maps of the setup, plus one dry USA map started in 1950 (a later start: more late
    towns).
    - **Layers**: `NAMES shapes ... layers=old:6,mid:6,late:4` on a 16-town map (from 1900: `late:5`); every `NAME town=`
      line has `layer=` and `x= y= alt=`. The biggest towns and the crossings, mouths and market towns are `layer=old`, the
      small plain ones `late`. Europe: old towns mostly -ham / -ton / -ley / -by / -thorpe / -bury / -ford or Aber- / Pen-
      / Llan-; the middle layer Market / Kings / Bishops X, St X, -field / -hurst / -wood; late -side / -haven / -port /
      New X. USA: old towns -ton / -ford / Mount X / Fort X / X Ferry / X Landing, the middle -ville / -burg / X City /
      X Springs and the personal names, late X Junction / X Heights / X Park / -view.
    - **Civic names** (Junction, Station, Center): only on `layer=late` towns, never on a town with `confluence` in its
      `tags=` or `cue=` (run 1729 had "Big Sandy Junction" at a fork).
    - **Tropical** (Europe list too, one load): no -thorpe / -by / -ham / -toft / -thwaite name; Port X, Xtown
      (Carolinetown, Fredericktown), X Bay / Point / Key / Cay, X Estate / Pen / Hall inland, Mount Pleasant-type and one
      or two St X (St Ann, St Elizabeth); `misfit=` may list `...:tropical/form`. USA tropical: Port X, X Bay / Point / Key.
    - **Dry** (USA): about a third of the towns, on one side of the map, Spanish (Agua Dulce, Arroyo Seco, Los Alamos,
      Las Lomas, San Felipe, Santa Rita); water names (Springs, Wells, Tank) where the town has water; rock colours
      (Painted, Vermilion, Ochre), Mesa / Butte.
    - **Subarctic** (England list): Fort X (Fort Fraser), X Landing / Portage / Rapids / Narrows, Glen- / Strath- / Kyle-
      names on the Gaelic edge (always three dialect areas); Swedish / Norwegian lists more -vik / -fjärd / -fjord / -fjäll
      / -fjell names than on a temperate map.
    - **Created towns by the year** (Quick 40 years, then Quick 40 again on a 1950 map): Works before 1920 often
      Ironbridge-style compounds (Forgebrook, Coalville) or "-Works" / Foundry / Forge; districts 1840-1945 sometimes
      "X Junction" / "X Station" / "New X"; districts from 1945 mostly X Heights / Park / Estate(s) / Acres / Gardens.
      A district's compass word (North X ...) only on the parent's side it sits on, never on a parent with one already
      ("South Ashby": no "North South Ashby").
    - **Leftover feature claims** (Generated / Landscape names, a map with a long river): `NAMES shapes ... left=` above 0;
      a district of a river town whose name doesn't carry the river: `DISTRICT ... event=create ... pattern=feature`
      ("Glavenside", "Usk Bridge") while the river is in at most two other names; the first bus stop of such a town away
      from the water: `STOPNAME ... claim=<River>` and a name with it ("Glaven Lane"), later stops without.

Send back: `make logs-grep PAT='NAMES|NAME town|WORKS .*create|DISTRICT .*create|STOPNAME|STYLE|CHARACTER'` for the
session, the climate of each load, and screenshots of a few coastal and inland names per climate.

## Bridge stops (2026-10-14; NEXT_PHASE_BRIEF 46; PLAN.md 6.3 "Bridge stops")

Checks that a bus stop on a town bridge takes a bridge name and that the 0814 bridge error is gone. Any map with an
Organic Towns river bridge or a town street bridge (seed `a`, or the Nelson / Sevenoaks style river towns); "Town and
stop names" Landscape or Generated (Generated gives river names: "<River> Bridge"), Debug log On.

1. While the towns grow: no `[SQOT] ERROR stage=snapshot ... ot_satellite.lua:240` line (run 0814 had 9); `BRIDGE
   outcome=plan ... edges=3` (no far cross street) lines appear as before.
2. Build a bus stop **on the bridge deck** of a town street bridge. A few seconds later: `[SQOT] STOPNAME ... new=<name>
   theme=bridge kind=bridge:river|town|old|new|street ... bridge=1 bridgeRead=edge river=<name>|-`. The name is
   "<River> Bridge" / "<Town> Bridge" / "Old Bridge" / "New Bridge" / "Bridge Street" (or the list language's form).
   `bridgeRead=near` means the stop's own edge wasn't found by its objects (the 6 m fallback decided): send the line.
3. Build a second stop on the same bridge (other side or other end of the deck): a different bridge name.
4. Build a stop on the **approach street** within ~60 m of the bridge end: `bridge=end`, "Bridge End" / "Bridgefoot"
   (de "An der Brücke", fr "Tête de Pont" ...).
5. Build a stop on a street away from any bridge: `bridge=0`, a normal name (as before this round).

Send back: `make logs-grep PAT='STOPNAME|stage=snapshot'` for the session, and a screenshot of the bridge stops' names.

## Names from the map's shape (2026-10-14; NEXT_PHASE_BRIEF 45; PLAN.md 6.3 "Names from the map's shape")

(2026-10-14, NEXT_PHASE_BRIEF 49: Landscape names now run the generator, so the list-name parts below (`match=`,
`nameCues=`, "a list name that says North") no longer apply; the survey, `cue=`, the word budget and the map checks do.
Run "Climate-led names" first.)

Checks the map survey (rivers, forks, the compass, big features), the word budget and the cue names on four new maps.
Run 0710's USA map (seed `a`) had 9 of 16 towns named Lake / Forest; now at most about 2 of each.

### Setup

- Quit TF3 fully, `make link` (done). Main mod (the dev mod is optional: its tour helps for the screenshots). Organic
  Towns: Act on **New towns only**, Debug log **On**, the rest default. Every map below is a NEW map with seed text `a`
  and the 0710 run's other map settings; only the name list and the "Town and stop names" setting change. Quit to the
  menu after each map once the names are on (`[SQOT] NAMES on=true`, a few seconds after the load).

### Steps

1. **USA list, Landscape names.** Right after the load, in this order:
   - `[SQOT] NAMES survey rivers= forks= mouths= bends= falls= lakes= sea= peaks= ranges= valley= bays= capes= narrows=
     isthmus= grid=128x128 cell=128 ... capped=- ms= s=`: `capped=-` (no phase over its cap, no timeout), `s=` a few
     seconds at most, `ms=` the survey's own time. Note the counts and whether they match the map you see (rivers that
     fork, a river reaching the sea or a lake, the big lake, a mountain range, bays). `rivers=0` on a map with visible
     rivers: send the line (the grid is 128 m, narrow rivers may be missed).
   - 16 `[SQOT] NAME town=... cue=... words=...` lines: `cue=` lists what the survey found at that town (`confluence`,
     `mouth`, `upper` / `lower`, `north` / `south` / `east` / `west` / `central`, `biglake`, `peak`, `summit`, `bay` ...);
     `nameCues=` the name's own cue words; `words=` the name's budget words.
   - `[SQOT] NAMES words used=lake:2,... held=... cap=2 near=5000 over=0 rare=... mode=landscape clean=`: every count in
     `used=` at most `cap=` (2 on 16 towns; -ford / -bridge style words up to 4), `rare=` low factors (0.3-0.5) on tags
     nearly every town read (lake, forest).
   - On the map: no two neighbouring towns (about 5 km) share Lake / Forest / Woods / Park / Hills / Heights; a "North
     ..." name only in the north (and so on); a town where two rivers meet may be "... Forks" / "... Junction"; no "(city)"
     or "city" leftovers in town or industry names.
2. **USA list, Generated names.** Same checks with `mode=generated`, plus `mount=` / `bay=` on the words line (the map's
   named mountain and bay, when it has them) and on the map: a fork town "Cedar Forks" / "Three Rivers" / "Middle Fork",
   towns along one river sharing its name ("Upper Cedar", "Lower Cedar", "Cedar Falls" by falls), compass names toward
   their edge ("North Bend"), "West Crystal Lake" on the big lake's west shore, "Mount Eagle" / "Eagle Gap" near the
   highest mountain. NAME `parts=whole:...` marks a whole-name form. Build a bus stop in a town by a named river (its name
   should use the river; neighbouring stops vary their last word: not three "... Road").
3. **A European list (England, or Germany), Landscape names.** As step 1: German maps show `-see` / `-wald` / `-berg` in
   `used=` at most `cap=`, Ober- / Unter- / Nord- names only where `cue=` says `upper` / `lower` / `north`.
4. **The same European list, Generated names.** As step 2: German Norder- / Wester- / Ober- / -münden / "an der <river>",
   English North / Lower / -mouth / Myton-style names where the cues are.
5. A reload of any of these saves: `NAMES on=false why=done`, no `NAMES survey` line, no town renamed.

Send back: the four sessions' `grep 'SQOT\] NAME' stdout.txt` (archived automatically), screenshots of the map with the
town names (or the Tour all towns shots), and which names read wrong or still repeat.

## Staggered satellites (2026-10-14; NEXT_PHASE_BRIEF 51; PLAN.md 6.3 "Staggered satellites")

Part of the "Seed a run" below (same setup: new map, seed `a`, Europe, 1900, Act on New towns only, Debug log On, the
dev mod). Run `2026-10-14_1927_sqot` had 3 satellites before year 1 and bursts (year 11: 3 seeds + Works + district).

1. After the load and `HEAD done`: no `SATELLITE ... kind=seed`, `WORKS event=create` or `DISTRICT event=create` yet.
   `grep 'SATPACE' stdout.txt` shows `outcome=wait why=notReady` / `why=spacing` lines (debug) for the grown towns.
2. Dev **Simulate**, **Quick: 40 years** (Move the game date off), as in "Quick 40 years at pace 0".
3. `grep 'SATPACE' stdout.txt | grep -E 'outcome=(found|refund|deferred)'`: each `outcome=found` line has
   `mapGrowth=` >= `need=`, and no two `found` lines share a `simYear=` (one per build round). Expect about 6-10 in all
   on the 16 towns, the first at simulated year ~8-12, then every 4-8 years. (Since §64, 2026-10-15: only Works and
   districts, 2-4 in all, SPACE_B 850: see "Combined test iteration" step 13.) `deferred` lines name the round's
   `winner=`: not always the biggest town. A `refund` (no site) is followed by another town's `found` in a later
   round, never two founds in one round.
4. `SATPACE summary why=simStop founded= decades=0-9:a,10-19:b,20-29:c,30-39:d years= minGap=`: every decade has
   some, none holds most of them, `minGap=` >= 4. Each `found` matches a `SATELLITE ... kind=seed`, `WORKS
   event=create` or `DISTRICT event=create` line of the same town right after it.
5. Grows: `SATPACE kind=grow outcome=found` lines spread over the rounds (not every pod in one round); `SATELLITE
   kind=grow` lines follow them.
6. Save, quit to the menu, load it again: `SATPACE event=init restored=true n=<the summary's founded>`; the next
   `found` only after `mapGrowth=` reaches `need=` again (no burst after the load).
7. Send: the SATPACE lines (or the session name) and whether the satellites look staggered on the tour.

## Seed a run (2026-10-14; NEXT_PHASE_BRIEF 44; PLAN.md 6.3 "Round after the 0502 run")

The user's map from now on: seed text **`a`** (Europe, 1900, the 0613 run's map settings). One mod run with this build
checks the round after the 0502 / 0613 runs: LEVELS on grown towns, the mature hold, satellite cores and bridge far banks
that fill, links, the name tags, a deep forest town, Quick's speed. **No vanilla baseline for `a` yet:** the comparison
page needs one true-vanilla run on `a` later (Organic Towns Act on **Off**, Vanilla town street angles **Game
default**, Town and stop names **Game names**, the dev mod's Quick 40 years + tour as here); not a required step now.

### Setup

- Quit TF3 fully (old Lua modules stay loaded), `make link` (done). Main mod + dev mod. Organic Towns: Act on **New towns
  only**, Town and stop names **Generated names** (as 0613; Landscape names also fine), Debug log **On**, Satellite towns
  **On**, Vanilla town street angles **Automatic**, the rest default.

### Steps

1. New map, seed text `a`, European, the 0613 run's map settings, 1900.
2. Right after the load: `[SQOT] LEVELS event=base from=firstSight towns=16 custom=<n>` and 16 `LEVELS read town= ...
   custom=<sig> base=<same sig> at=load` lines, then `LEVELS read at=load towns=16 custom=<n> changed=0`.
3. OT Dev, Simulate: no need to wait for the head start. Seed 1, Every town grows on, Tour on, screenshots on, Move
   the game date off, **Quick: 40 years** right after the load: it ends the head start at once (`[SQOT] HEAD done ...
   cut=simgrow left=<n>`) and the first simulated year gets a build round in its place (SIMGROW round year=1).
4. Wait for `SIMGROW stop`, then the tour (`SIMGROW tour wait=create` -> `wait=done` when a creation is in flight).
5. Save ("sqot a"), quit. Tell Claude the session name (the log is archived).
6. Optional: build two or three bus stops in a town by a river or lake (Generated names: their names should use the
   town's generated river / lake name, STOPNAME lines).

### Checklist (log lines)

1. No crash, no freeze; `grep -cE 'SQOT[_A-Z]*\] (ERROR|WARN)'` = 0.
2. **LEVELS:** on grown towns (mat >= 0.5) `LEVELS ... action=set why=sparse owner=engine ... mat= k=` (0613: `skip=player`
   on all 8). `LEVELS read ... at=simgrow:year=N` lines after each round: a town listed there changed its weights (`was=`
   the old sig): tell whether the engine changes them (that would read as `owner=player` afterwards). No `owner=player`
   on a town nobody edited.
3. **Mature hold:** `MATURE town= event=cap|hold mat= free= line= demK=` on the grown towns, CHECK `why=mature` on them in
   the second half, never on a town at `mat=0.00`. Grown towns' ALLTOWN `pb=` above the young towns' (0613: 2.82 against
   2.95); the median above 0613's 2.92. Level 3-4 stay 0 before 1950 (expected).
4. **Satellites:** `SATELLITE ... coreEdges=3`; `FILL ... why=leadEnd` at every seed build (no `skip=surge` for them), then
   `FILL ... why=satCore dose=1 of=2` ~45 s later and `FILL effect ... near=0->n` with n > 0; `SATELLITE retire` only for
   seeds still empty after both doses. In the shots: no empty "H" skeletons (0613: Thornby x2, Thurgrove, Little
   Skeghurst, Mershaw, Wooddale, Holtbottom).
5. **Bridges:** `BRIDGE ... outcome=built ... approach=<= 260 bowed= crossLater=true`, then `FILL ... why=bridgeEnd`; no
   empty cross street on the far bank in the shots; a long approach bends once.
6. **Links:** DISTRICT / WORKS `event=link` with `tries=` up to 5 and `outcome=built` on most (0613: 1 of 7); fewer `why=back`.
7. **Works:** the Works towns' CHECK `uses=<res>/<com>/<ind>` and `initials=10/10/200`: is the industrial share built?
   Their shots: workshops / warehouses rather than houses.
8. **Deep forest:** `FOREST ... mode=deep why=ring=..` for 1-2 towns (0613: none; the most wooded rings 0.37 / 0.32 by the
   old count); `notDeep` lines show `share:ring=..,sectors=n` for the others.
9. **Names (Generated):** NAME `tags=` no longer show `edge:0.70` and `ash` on every town; no vale / dale / glen / strath
   on flat towns; `read=...,riv:n/w@d` on river towns, `river=<name>` on Thurgrove-like towns with rivers 300-400 m out;
   NAMES `rivers=` more than 1; no "tarn" lake on low ground, no "Upper" at the water level.
10. **Speed:** `SIMGROW year ... added= perS=`; `SIMGROW stop s=` about **0.7 s x quiet years + buildings added / 90** (0613:
    172 s estimated, 182 s measured); no `[SQOT] HEAD` line after `SIMGROW start`; no `FILL kind=dose|upward` with
    `timeouts>0` inside a round (rounds skip them: FILL `skip=sim` debug); round builds at most 3 per town (`per=` field).
11. **Tour:** every `SHOT ... fallback=false` or a `SHOT reaim` before a fallback shot; shot 1 centred on its town.

### Lines to send

`grep -E '\[SQOT(_DEV)?\] (LEVELS|MATURE|SATELLITE|BRIDGE|FILL|DISTRICT|WORKS|NAMES|NAME town|SIMGROW (start|year|round|stop|tour)|SHOT|ERROR|WARN)'`,
the ALLTOWN lines, or just the session name (it is archived).

### Compare (single-run page until a vanilla run on `a` exists)

```
uv run plans/square_organic_towns/compare/build_compare.py --single <session>:<load> --label 'Mod <hhmm> (seed a)' \
    --dir mod --out plans/square_organic_towns/compare/<date>_a_<hhmm> --shot-px 1600 --shot-q 50
```

`<load>` is the map load with the SIMGROW stop (`:N` = the N-th `Init game took`). Optionally put it beside the 0613 run
on its page (same seed, so towns pair by id): `--out plans/square_organic_towns/compare/2026-10-14_a --add
<session>:<load> --label 'Mod <hhmm>' --dir mod-<hhmm>`. Once the vanilla run on `a` exists: `--add <vanilla
session>:<load> --label 'Vanilla' --dir vanilla` to the same page. Then a dated section in BASELINE_VANILLA.md.

**Run 2026-10-18 22:22Z** (session `2026-10-18_2222_sqot`, load 1: `Map seed text: a`, EU, 1900, dev Quick 40 years
with the tour; this build: plain streets only, the 44 m minimum block with the growth-front relaxation, close the gap
(§74), away from player facilities; added to the compare page `compare/2026-10-15_a-lock` as run `mod-2222`, beside
the §71 run `mod-71` = `2026-10-16_1846_sqot`). No save (step 5 skipped: normal shutdown after the tour).
1. **Pass.** No crash, normal shutdown; `SQOT[_A-Z]*] (ERROR|WARN)` = 0. One FAILED build (Merehythe-on-Redwater
   22:23:34, 1 edge, `msgs=Collision`), the game's refusal as in earlier runs.
2. **LEVELS: pass.** `LEVELS event=base from=firstSight towns=16 custom=0`, `read at=load ... changed=0`; 7 `action=set`
   (7 `why=fill`, 2 `why=sparse` among the LEVELS lines), 2 `action=clear`, 0 `owner=player`.
3. **Mature hold:** MATURE `event=cap` lines (Two Waters `mat=0.21`, Merehythe 0.05, Far Ashworth 0.06 ...), CHECK
   `why=mature` 1; level 3-4 capacity 0 (expected before 1950).
4. **Satellites: n/a** (all 16 `why=retired`, as since §64: offshoot towns instead).
5. **Bridges:** none (as in the §70 / §71 runs).
6. **Links: 3 of 4.** Merehythe Forge (Works, 514 m, 6 edges), Blackmerehall (district of Seven Oaks, 163 m), Wheatden
   Timber Yard (212 m) linked; Two Waters Riverside (shore district, year ~12) has no link line.
7. **Works:** Merehythe Forge (plain) and Wheatden Timber Yard (timber, beside the timber industry); not judged from the
   shots.
8. **Deep forest:** Dovemouth-in-the-Forest `forest=0.35:deep` (ring 0.48).
9. **Names:** not checked this run.
10. **Speed: pass.** `SIMGROW stop ... buildings=1991->9212 s=125 sPerYear=3.1` (§71: 9384, 132 s), 11 rounds, 179
    round builds, fails 0.
11. **Tour: pass.** 20 SHOT lines, all `fallback=false`, one `SHOT reaim` (Two Waters, off=833); shots in
    `~/Library/Application Support/Steam/userdata/65263351/3493540/local/screenshots/2026-10-18_15-25-10_img_0.png`
    .. `15-26-07_img_19.png` (the Mac's local time is UTC-7).

New in this build:
- **Plain streets only: pass.** 0 ENTRY lines (the §71 run: 19), PLAN `trees=-` on every plan (§71: `trees=1` / `2`
  on 3), INIT `trees=off`, no `_trees` / `_tram` / `_bus` / `barrier` template in the log, no `specialJoin`; the shots
  show plain grey streets only (no tree rows). A player-built variant dead end was not on this map.
- **Wider minimum block / close the gap / player facilities:** results in their own sections above.

Shots (main questions):
- **Organic quality:** the best towns read well: Two Waters (radial organic core by the river, blocks fairly even),
  Dovemouth-in-the-Forest (bigger and less knotted than in §71, organic, woods kept), Seachurch Cove (compact branching
  MED hill harbor town), Hornholt Isle, Merehythe (organic along the shore). Weak spots, mostly as before: Watersmeet's
  west half a zig-zag "staircase" street and parallel rakes, an empty Y-fork of bare streets east of it; Dalemere's
  south edge still two big rectangular loops and a square loop without houses (noted in the §71 run too); Wheatden and
  Little Dalemere empty loops at the edge; Shaw a few bare spokes; Seven Oaks a dense knot of short curved streets
  (mostly the game's own fill: its game street length 9.6 vs 5.4 km in §71). Unhoused street share about as before
  (empty length 24.7 vs 22.1 % median per town).
- **Clusters (form `clustered`: Seachurch Cove, Watersmeet, Dalemere):** tighter than in §71: Seachurch Cove radius
  425 vs 614 m, `spread` 1.12/0 vs 1.44/14, dens 12.0 vs 4.7, empty street 0.19 vs 0.23; Dalemere 0.26 vs 0.30 empty;
  Watersmeet about the same. Offshoot clusters: Blackmerehall a compact clump on its link; the Forge and the Timber Yard
  small radial clumps on the country road; Two Waters Riverside a loose shore strip without a link.

**Run 2026-10-19 00:24Z** (session `2026-10-19_0024_sqot`, load 1: `Map seed text: a`, EU, 1900, dev Quick 40 years
with the tour; this build: "Close the gap" less cautious, otherwise as 2222; compare page run `mod-0024`). After the
tour the user loaded the save "Organic Towns - Subarctic" in the same session (00:30Z on); only load 1 is read here.
- **Pass:** no crash, `SQOT[_A-Z]*] (ERROR|WARN)` = 0 (2 game GUI tracebacks "Ignoring Set() on expired ReactRefWrap",
  as in 2222); `SIMGROW stop ... buildings=1992->8911 s=128 sPerYear=3.2`, 11 rounds, 176 round builds, fails 0;
  tour 20 SHOT lines (one `fallback=true`: Two Waters), shots `2026-10-18_17-28-25_img_0.png` .. `17-29-19_img_19.png`.
- **Plain streets: pass.** 0 ENTRY, no `_trees` / `_tram` / `_bus` / `barrier` template, no `specialJoin`, no PLAN
  `trees=` count.
- **STALL 0, STUCK 3** (Hornholt Isle year 24 `held=wedge=2,env=2`, Ashgrove year 32 `wedge=1,env=3`, Wheatden year 32
  `wedge=12,env=12`); 2222: 0 / 2. Empty plans 102 vs 100. FAILED 3 (no join; see "Close the gap").
- **Totals (16 towns) vs 2222:** persons 44432 vs 44155, capacity 44342 vs 43782, buildings 8911 vs 9212 (pb median
  5.06 vs 4.86), persons / ha median 37.2 vs 39.3, median radius 474 vs 457 m, `spread` 1.27 vs 1.23, dead ends 331 vs
  305 (per km 1.61 vs 1.55); mod streets 106.1 vs 97.3 km, the game's own 89.9 vs 99.8 km (share 0.46 vs 0.51).
  Seachurch Cove 544 buildings (2222: 678, §71: 552), Seven Oaks 553 (702) with less game street (11.8 vs 17.3 km).
- **FAC:** still 17 identical lines (1 at 00:26:08, 16 at the SIMGROW start 00:26:14: one per town), the `facSig`
  oddity of the 2222 run.
- **Shots:** organic quality about as in 2222. Watersmeet better (closed curved loops in the east half instead of the
  Y-fork of bare streets; still two long empty streets beside the river and a game-grown grid quarter across the
  bridge); Seachurch Cove looser and less knotted (curved loops, fewer stubs); Dalemere much the same (one squarish
  loop at the east edge); Seven Oaks now a linear town along the road with a bare hook loop and a bare diagonal at
  its south end. The joins themselves can't be told apart at 1800 m.

## Deep forest towns (2026-10-14; NEXT_PHASE_BRIEF 43; PLAN.md 6.3 "Deep forest towns")

1-3 towns per map in dense forest plan as **deep** forest towns: winding streets, every street near the trees locked,
small woods inside the town kept, more forest lanes, a quarter of the clearing budget, no districts / Works / level
weights. Shares the "Seed a run" above (same setup and steps, nothing extra to do); a heavily wooded European / Nordic
map shows more of it. (2026-10-14: run 0613 on `a` picked none, the rings read 0.37 at most; the pick now counts the ring
at a lower cell threshold, 0.40 share, woods on 5 of 8 sides: NEXT_PHASE_BRIEF 44.)

### Steps

1. As the "Seed a run" (new map, seed `a`, 1900, Act on New towns only, Debug log On). After `HEAD done`, grep the
   picks: `grep -E '\[SQOT\] FOREST .*mode=deep' stdout.txt`. None on that seed: a second map, European, high forest,
   hills, 1900, same check.
2. If still no town is deep: OT Dev, Town tab, pick the most wooded town (FOREST `share=` debug lines, or the Forest lane
   test's LANETEST `pick=`), **Force deep forest** (DEEPDEV), then Grow now 2-3 increments (or let the Simulate run).
3. Simulate (Quick 40 years) with the tour; screenshot each deep town from above and at street level.
4. Save, reload the save once (does the town stay deep?), let it build once more, quit. Send the session name.

### What to look for

1. `FOREST town= name= mode=deep why=ring=..,p=..,u=..` for 1-3 towns (`count=` at most 3); `notDeep` debug lines show
   the others' reasons (`share:ring=` with `,sectors=n` when the share passed, `draw:`, `quota:`, `style:`, `tier`, `framed`). After the reload: the same towns
   `why=saved`, no new deep town among the framed ones.
2. STYLE `forest=<share>:deep deep=<why>`; ALLTOWN `forest=<share>:deep`.
3. PLAN of a deep town: `forestMode=deep`, `deepLocks=<n>/<edges>` mostly all, `maxStraight=` under ~80 m,
   `bends=` more than half of the edges, `groveHeld=` > 0 where it has small woods inside, `lanes=`, `forestBudget=`
   small (a quarter of the hug value), `geoBad=none`. FOREST `lock= side= near= tip=` debug lines.
4. FORESTLANE lines of the deep town: `why=deep:p=0.67,...`, up to 8 per town; `outcome=built`, no houses on them.
5. No DISTRICT / WORKS for it (`why=deep` debug once), no LEVELS `action=set` for it.
6. In the shots: winding, wooded streets; small woods left standing inside the town; clusters in clearings joined by
   lanes; the game's own streets not branching into the trees off the locked streets.
7. **Size:** the deep town's buildings over the 40 years against its target (CHECK `cap=<actual>/<target>`) and against
   a hug town of the same size: it may stay smaller (many locked streets, little clearing). A town stuck with empty PLANs
   (`edges=0 forestHeld=` again and again) is the risk to report.
8. No crash, no freeze (`grep -cE 'SQOT[_A-Z]*\] (ERROR|WARN)'` = 0); no "Construction not possible" refusals on deep
   towns' winding pieces (REFUSED / DIAG lines).

Lines to send: `grep -E '\[SQOT(_DEV)?\] (FOREST|STYLE|PLAN|FORESTLANE|DEEPDEV|BUILT|REFUSED|CHECK)' stdout.txt` for the
deep towns' ids, or just the session name.

## Simulate speed-up and Build out (2026-10-14; NEXT_PHASE_BRIEF 41; PLAN.md 6.3 "Simulate natural growth" "Speed-up and Build out")

Dev mod only. Run it as part of the "Seed a run" above (seed `a`). Quick done in runs 0502 / 0613 (BASELINE_VANILLA.md);
since 2026-10-14 (NEXT_PHASE_BRIEF 44): at most 3 builds per town and
round, no dose / upward fills inside rounds, SIMGROW year `added= perS=`. Build out is still open. Any Simulate start
cuts the main mod's head start (`HEAD done cut=simgrow`, a build round in year 1 instead; until later on 2026-10-14
Quick waited, greyed, for `HEAD done`, several minutes).

### Quick 40 years at pace 0 (the Seed a run's step 3)

- OT Dev, **Simulate** tab: Seed 1, Every town grows on, Tour all towns when stopped on, "Move the game date" **off**
  (the comparison needs the same calendar); Camera & tour: screenshots on. Quick works right after the load: it
  cuts the head start (`HEAD done cut=simgrow`) and runs a build round in year 1.
- Press **Quick: 40 years** (green). It sets Real s per year **0 (as fast as possible)**, Fill every **4**, Fast fill,
  Build round, Game speed 8x.
- `SIMGROW start mode=quick ... pace=0 ... fillEvery=4 ... inflight=24 reachM=700`.
- Expect `SIMGROW stop s=` about **0.7 s x 30 quiet years + buildings added / 90 per s** (run 0502: 18,170 buildings
  added, 231 s; 0613: 13,550, 182 s against 172 estimated; 0302: 6,238, 175 s before the speed-up). The year lines'
  `perS=` should read ~80-100 in the fill years. Quiet years: `SIMGROW year s=0.1-0.5`; fill years: `fillEarly=` >
  0 in most, `fillS=` 4-10 (no 15-20 s fills), no `[SQOT] BUILT` (the main driver's own) between a `SIMGROW round` line
  and its year line, BUILT `ms=` under ~1500 during rounds.
- Same targets as 0613: the year-40 `SIMGROW town ... target=` per town equals the 0613 run's (same seed `a`, same rates).
  Buildings, round builds and the mod share differ by timing (send the SIMGROW year / round lines).

### Build out (after the Quick run, or on a fresh map)

1. Optional: check **Move the game date with the simulated years** (to see level 3-4 buildings: the date jumps to
   the start year + the simulated years at each chunk, forward only; changes the save's date for good). Off: the map
   stays at its start year, a 1900 map never gets level 3-4 town buildings (era limits 1950 / 1990, towns.md).
2. Press **Build out: 100 years** (green, its own section in the Simulate tab). It always starts fresh from the towns'
   current size: 100 more years in 10 chunks, every town grows, the tour at the end.
3. `SIMGROW start mode=buildout chunks=10 years=100 ... upGap=gap8s pace=0 even=true tourWhenDone=true roundBuilds=8
   roundMaxS=25`, then per chunk a `SIMGROW round` and a `SIMGROW chunk chunk=k of=10 years=10 year=<10k> s= ... fillS=
   fillEarly= round=` line; with the date on, `SIMGROW date year=<start+10k> ok=true` per chunk.
4. `SIMGROW stop reason=limit years=100 ... upGap=restored mode=buildout`, then the tour (`ALLTOWN`, shots).
   Expect **~3.5-4 min** for 16 towns from a fresh map (the forced houses come at ~100 per s); after the Quick run
   longer (bigger towns). Upward doses (`[SQOT] UPWARD`) and `LEVELS` lines during the rounds, about once per town
   and chunk at most.
5. Send: `SIMGROW (start|chunk|round|date|stop)` lines, the tour shots; say whether the mature towns look right.

## Fresh run after the comparison round + Angle split run (2026-10-14; NEXT_PHASE_BRIEF 39; PLAN.md 6.3 "Round after the same-seed comparison")

One game session, two new maps on the user's seed (seed text `a` since 2026-10-14; was the comparison seed `U8Qxgisp4I`
of run `2026-10-14_0119_sqot`: European, the same size and town count), both with the new build. Run A of this section
was done as `2026-10-14_0302_sqot-sqrl` load 2 on `U8Qxgisp4I`; run B (the angle split) is open. On `a` the vanilla side
of the comparisons below needs the true-vanilla run on `a` ("Seed a run" note); until then compare A with B only. Run A measures phases 1-3
(the mod's defaults: the EU 35° street angle); run B is the **angle split**: the same mod growth with the base 0° angle, so
A vs B is the angle alone and B vs the 0119 vanilla load is the growth driver alone. Can run together with "Addendum
after the 0119 run" / "Round after the 2355 run" below (a different map), but not on the same load.

### Setup

- Quit TF3 fully, `make link` (done). Main mod + dev mod. Organic Towns settings: Act on **New towns only**, Town and
  stop names **Landscape names**, Debug log **On**, Satellite towns **On**, the rest default.
- "Vanilla town street angles": run A **Automatic** (the default), run B **Game default**. (Game default writes nothing:
  the driver never reads the angle, PLAN.md 6.3.)

### Steps (each run)

1. New map, seed text `a`, European, the 0613 run's map settings, 1900 (Quick may start right after the load: it cuts the head start).
2. Check the first lines: run A `[SQOT] ANGLE choice=auto ... angle=0/0->35`; run B `ANGLE choice=default ...
   angle=0/0->0` (no 35). Both: `INIT ... capsBoost=0 ... levels=pbAim4.5`.
3. OT Dev, Simulate: Seed 1, Every town grows on, Tour on, screenshots on, **Quick: 40 years**. Wait for `SIMGROW stop`,
   then (if a district or Works was being created) `SIMGROW tour wait=create` -> `wait=done why=created`, then the tour.
4. Save ("sqot cmp A" / "sqot cmp B"); quit to the menu; start run B the same way.

### Checklist

1. No crash, no freeze; `grep -cE 'SQOT[_A-Z]*\] (ERROR|WARN)'` = 0.
2. **No capacity boost:** every `FILL restore ... initials=a->b->c capsBoost=0` has c = a (the pre-fill values). The
   SIMGROW year-40 `target=` per town equals the 0119 vanilla load's for the same town id (the build script's key
   notes: persons and targets x1.00, the 0119 mod run had x1.16).
3. **Density:** ALLTOWN `pb=` median **>= ~4.5** (0119 mod: 2.93, vanilla 6.37), `freeLots=` near 50-55 % (0119: 58 %),
   street per person well under 7.6 m. CHECK `freeK= pbK= demK=` (demK ~0.1-0.3 on sparse towns, 1 on dense ones),
   `why=free` on towns with many free lots. `LEVELS ... action=set why=sparse pb= k=0.25..1 weights=...
   lvl=a:<actual shares>` on the sparse towns (new map only), later `action=set why=change` as they densify or
   `action=clear why=dense` at 5.5; `LEVELS ... ok=false` should not appear (send it if it does). ALLTOWN `lvl=a:` shares
   moving toward levels 3-4 over the years (compare with run B and vanilla). UPWARD fires more (no `skip=surge`).
4. **Straight lanes:** SATELLITE seed lines `link=400-900 laneEdges>0 straight=<=150`, `FILL ... why=leadEnd` after a
   seed; PLAN `straight=<m>/<n>` (n > 0 = the guard cut something: fine, note how often). In the shots: no long straight
   empty lane with a T (Ellesmere S, Winchcombe W, Windermere SW, Henley-in-Arden S in 0119), satellite links winding and
   unhoused (country lanes), the satellite core housed.
5. **Measurement:** every ALLTOWN line has `ind=<n>/<enclosed>[:files]` and `lvl=a:..,u:..,w:..,c:..`; the districts /
   Works created before the tour have their ALLTOWN line and a shot.
6. **Form kept:** run A's towns still read organic in the shots (orient orth ~0.3 like 0119), spread median ~1.2, the
   shaped towns' arms and fingers still visible.

### Compare (after the session is archived; `make logs` lists it)

```
uv run plans/square_organic_towns/compare/build_compare.py --a <session>:1 --b <vanilla a session>:<load> \
    --label-a 'Organic Towns (new)' --label-b 'Vanilla' --out plans/square_organic_towns/compare/<date>_a_new
uv run plans/square_organic_towns/compare/build_compare.py --a <session>:2 --b <vanilla a session>:<load> \
    --label-a 'Mod growth at 0°' --label-b 'Vanilla' --out plans/square_organic_towns/compare/<date>_a_angle0
uv run plans/square_organic_towns/compare/build_compare.py --a <session>:1 --b <session>:2 \
    --label-a 'Mod at 35°' --label-b 'Mod at 0°' --dir-b mod0 --out plans/square_organic_towns/compare/<date>_a_angle
```

`:N` = the N-th map load in the log (split at `Init game took`). Each folder gets `data.json` and the downscaled shots (view
them on the site: `make site-media && make site-dev`, Organic Towns → Map comparisons: side by side / slider); `--verdicts file.json` adds per-town verdicts. Compare these
ALLTOWN / SIMGROW fields (the page's summary table): `pb=` (persons per building), `buildings=`, `capacity=`, SIMGROW
`persons=` / `target=` (year 40), `streetLen=` / persons (street per person), `emptyLen=` / `streetLen=`, `freeLots=`,
`deadEnds=` per km, `orient=` (grid vs organic), `spread=`, `r=` and `dens=`, `ind=` (enclosed industries), `lvl=`. Then
add a dated column to BASELINE_VANILLA.md "Same-seed comparison" (or a new dated section) as before.

Log lines to send: `grep -E '\[SQOT(_DEV)?\] (INIT|ANGLE|LEVELS|FILL restore|UPWARD|SATELLITE|SIMGROW (stop|tour)|ERROR|WARN)'`,
the ALLTOWN lines, or just "done" + the save names: the session is archived.

## Addendum after the 0119 run (2026-10-14; NEXT_PHASE_BRIEF 38 addendum; PLAN.md 6.3 "Round after the 2355 run" addendum)

Run it together with "Round after the 2355 run" below (same setup: new hilly, wet, **wooded** European map), plus one
load of the `2026-10-14_0119_sqot` save (the race save) first.

1. **The 0119 save, loaded once** (Debug log On): `OFFSHOOT event=drop town=147514 name=Heywood_Works kind=district
   parent=61041 parentName=Ringwood why=far`, then `OFFSHOOT event=adopt` for Heywood_Works (kind=works, parent
   61042) and for Winchcombe_Heath, Ringwood_Bay, Tickhill-on-Sea, Windermere_Sands (kind=district, their parents),
   no `ERROR`. A second load of the saved game afterwards: no drop line (the save is clean), no adopt line.
2. **One creation in flight:** on the new map, DISTRICT / WORKS `event=create` lines never overlap: each `create` is
   followed by its own `created` (or `refused` / `created ... why=unidentified`) before the next `create`, anywhere on
   the map.
3. **`created` names match:** every `created ... name=<X> how=name+pos` has the same name as its `create ...
   district=<X>` / `works=<X>` line from the same parent; no town id in two `created` lines;
   `why=unidentified` should not appear (if it does: send the log).
4. **No forest districts:** `create ... forest=<share>` at most 0.20 on every line (`-` when outside the parent's tree
   grid), often `+edge`; `event=none why=forest` or `rejects=forest:n` on wooded parents. Fly to each new town after
   the 40 years: no town grown into a forest that was there; open land, maybe along a forest edge. No `kind=clearing`.
5. **Links:** no `link outcome=none why=far fails=far:24` (that was the wrong town); `linked` for most.
6. **Districts / Works without transport stay put:** `OFFSHOOT event=hold` (debug) once per new town and street count; no SEND / BUILT
   lines for a Works / district town under 120 buildings.
7. **Names:** the Works on the map use different suffixes (not three "... Works"), districts not all "-on-Sea" /
   "Sands"; no water word twice ("Windermere Sands", "Ellesmere Port-on-Sea"). From 1950 on a new map, estates / parks.
8. **Setting:** a quick second new map with Satellite towns: Off: no DISTRICT / WORKS `create` line at all.

## Round after the 2355 run (2026-10-14; NEXT_PHASE_BRIEF 38; PLAN.md 6.3 "Round after the 2355 run")

The previous run's results: HISTORY.md (2026-10-14, "Round after the 2240 run", session `2026-10-13_2355_sqot`) and
the vanilla comparison BASELINE_VANILLA.md. New this round: district towns, Works by a factory with a working link,
coastal huggers, more bridges, squeezed towns, street-aware stop names, Act on Off does nothing, denser growth, shorter
curved lanes ahead. Grep both prefixes (`\[SQOT(_DEV)?\]`).

### Setup

- Quit TF3 fully, `make link` (done). Main mod + dev mod, Debug log On, Town and stop names: Landscape names, Act on:
  New towns only (the default).
- **New map**: European, Large, **with coast, lakes, rivers, hills and forests** (a hilly, wet, wooded seed; more
  water than last time), many towns, 1900, industries on.

### Steps

1. Load; wait for `NAMES` and `HEAD done` and a few CHECK lines (~2 min). Look for `COASTAL pick=` (once).
2. **Stops along one street:** pick one long, fairly straight street (500 m+) in a town; build 6 bus stops along it
   about 150-200 m apart (both directions from the first, one up a slope if it climbs). Then 6-8 scattered stops
   elsewhere (centre, shore, wood, outskirts, by an industry). Wait ~10 s after each.
3. **Station by an industry:** one passenger rail station within ~300 m of an industry (farther from the town centre
   than from the industry), one in a town centre.
4. Optional: OT Dev, Town tab, pick a big town -> **Found a district**; when `DISTRICT ... event=created` shows,
   press it again (links it now). Fly there.
5. OT Dev, Simulate: Seed 1, Every town grows on, Tour on, screenshots on; **Quick: 40 years**. Leave it until
   `SIMGROW stop` and the tour shots. Save ("sqot 2355 round").

### Checklist (crashes first)

1. No crash, no freeze; `grep -cE 'SQOT[_A-Z]*\] (ERROR|WARN)'` = 0.
2. **Districts:** `DISTRICT ... event=create district=<name> src=composed|real:<tag> kind=upper|shore|across|lead|valley
   (no clearing since the 0119 addendum) kinds= d=600-1500 caps=200/30/10` -> `event=created` -> `event=link outcome=plan tries=k/n pair= route= detour= joined=2`
   -> `event=linked`. Or `event=none why=noSite` / `on=false why=` (debug). Fly to each: a small residential town on
   its feature (hilltop above the town, by the shore, at the lane's end ...), a road to the parent, houses between
   them after the years. Up to 2 per town, quota one per 4 towns. STYLE `districtKa=0.75` on the parents (their arms
   reach less). PLAN `gaps=... waive=1` on the parents (the gap waived along the link).
3. **Works by a factory:** `WORKS ... event=create works=<Town> Quarry|Colliery|Works|Mills|... kind=<industry kind>
   industry=<kind>:<m> at=0.55-0.73 nudge= d=` (or `kind=harbour|rail` when nearer), then **`event=link outcome=plan
   ... joined=2` and `event=linked`** (the 2355 run had none). Fly there: the Works between the town and its factory,
   linked by a country lane.
4. **Coastal huggers:** `COASTAL pick=<names:score> n=1..2`, then per town `COASTAL town= applied=true form=shore
   shape=shore depthCap=150-230 front=true`. After 40 years: a long shallow strip along the coast both ways, a
   waterfront street. `applied=false why=` when the shoreline can't be followed.
5. **Bridges:** BRIDGE lines: more `outcome=plan` (narrow lake arms, river bends: `narrow=` > 0 on more towns),
   `skipped=` (candidates dropped for obstacles beyond the snapshot / another town), `try=1..3`, `key=`; a refusal
   followed by another candidate at a later build (`try=2`). `outcome=built` hoped for. Send any `outcome=failed`
   with the game log's `ProposalData error` line above it.
6. **Stop names:** the 6 stops on one street: one base name (`STOPNAME ... section=<key>:<len> base=-`), then
   variants (`kind=variant:compass|up|down|old|new|far|mark|compass+... base=<the first name>`): "Bay Road East",
   "Upper Bay Road", "Old Bay Road", "Bay Road End" ... All unique on the map, none over 28 characters, no
   "Old Henley-in-Arden Road", no "Bay Quay". The scattered ones: their own names (`base=-`).
7. **Act on: Off** (optional, a separate quick load with Act on Off): `[SQOT] PRERUN actOn=off writes=none`, no ANGLE /
   TOWNSIZE / INDSTREETS line, `INIT on=false`, no NAMES line.
8. **Density:** CHECK `freeK=` (< 1 where many lots are free) and `pb=` (persons per building, aim >= 4.5 since
   NEXT_PHASE_BRIEF 39, was > 3.5); UPWARD lines with `why=sparse` (towns of 250+ buildings under 4.5 persons per
   building since 39; 400+ under 4 before): `ups=` well above 0-1 per town.
   ALLTOWN `pb=` / `emptyLen=` / `emptyEdges=` / `deadEnds=` / `streetLen=` / `freeLots=` for every town; SIMGROW year
   `frames= gapHeld=`.
9. **Lanes ahead:** `LEADLANE ... len=250-600`, curved (shots), more `endKind=ribbon`; none on towns with a district;
   FILL `why=leadEnd` after each built lane; fewer long straight empty lanes ending in a T (Chipping Campden-like).
10. **Squeezed towns:** STYLE `squeeze=` (0..1); towns between slopes / water / forest with squeeze >= 0.5 more often
    `form=clustered` (formWhy weights). Hills, canyons, valleys keep their shapes.

### Log lines to send

`grep -E '\[SQOT(_DEV)?\] (INIT|PRERUN|COASTAL|DISTRICT|DISTRICTDEV|WORKS|BRIDGE|STOPNAME|LEADLANE|UPWARD|REFUSED|ERROR|WARN)'
stdout.txt`, the ALLTOWN lines and the SIMGROW year lines. Or just "done" + the save name: the session is archived
(`make logs`).

## Log lines

| Line | When | Look at |
|---|---|---|
| `INIT on=… reason=… region=… profile=… nameList=… climate=… lock=… fill=… metropolis=… params=…` | once per load, first frame of the map | `on=true`, `region=US`, `profile=NA_GRID`, `nameList` not `nil`; `params` shows the raw param values (1-based) |
| `SAVE event=init try=N fresh=… known=N gameTime=…` | "New towns only", first time on a save | `fresh=true` on a brand-new map, `known=<town count>` on an old save |
| `RUN actOn=… knownTowns=N` | when the driver starts working | |
| `CHECK town=… buildings=… r=… free=… open=… openEdges=… gaps=… virtual=… built=… need=… cap=… capRatio=… demand=… perEdge=… ownOpen=… ownEdges=… lead=… why=… needsRoom=…` | debug log on; every town check (one per 3 s) | `demand` = edges of target growth since the town's last build (`perEdge` persons each); `ownOpen` / `ownEdges` = open lots / edges on the mod's own streets, held under `lead`; `open` = open frontage (free lots on edges under 25 % built + `virtual` lots on not-yet-adopted streets), compared with `need`; `gaps` = free lots on fuller edges (not counted); `why` = demand (build) / ahead (demand, own streets still empty) / low (build) / open / over (shrinking). Trigger: PLAN.md 6.3 "Growth-demand trigger" (6.2 "Trigger" for room) |
| `SNAPSHOT … deadEnds=N joinable=N noJoin=reason:count/…` | debug | `joinable` > 0 for growth; `noConfig` = our own unadopted dead ends (never joined) |
| `STYLE … axisDeg=… axisSource=streets|saved … form=… formWhy=… shape=…` | debug, once per town | `saved` after the town's first build (and after a reload); `form` (v8: clustered / radiating / sprawling / linear / wide / fingers, `-` for towns with a saved frame from before forms or a dev-forced shape), `formWhy` = forced / saved / `shape:<id>` (site-picked shape) / `draw:` weights |
| `PLAN town=… edges=… joins=… minR=… minAngle=… maxKink=… maxCorner=… shortest=… geoBad=… us=…` | debug | planning time `us` (µs); the offline geometry checker (`ot_check`) over the planned edges: `minR` smallest Hermite curve radius (m, `inf` = all straight; must be ≥ 70), `geoBad=none` expected |
| `REFUSED town=… why=precheck msgs=… collisions=…` | debug; the pre-check refused, next try has half the edges | |
| `SEND town=… spec=edges=…_joins=…_cfgRemove=…_cfgAdd=… preCost=… open=… balance=… player=on\|off` | **always**, right before every build | crash forensics: this is the last line before a crash; `player` = context with the player (dev toggle "Build as player") |
| `DIAG town=… i=… edge=… key=… class=… join=… len=… arc=… minR=… dev=a/b slope=… p0=… t0=… t1=… msgs=… collisions=…` | dev mod loaded: after a pre-check refused with `Construction_Not_Possible`, and on every Plan only | one line per new edge whose **own** pre-check (the edge alone with its two nodes; a join edge with its D3 joint) failed, at most 6. `len` chord, `arc` tangent length, `minR` its curve radius, `dev` tangent vs chord at both ends (deg) |
| `DIAGSUM town=… whole=ok\|refused tested=N failed=M player=… geo=bad=…_minR=…_… us=…` | after the DIAG lines | `failed=0` with `whole=refused` = no single edge is the problem (their combination, the joints or the town around them are) |
| `BUILT town=… ok=true edges=… ms=… cost=… balance=a->b found=N trigger=… locked=N` | always, build callback (`found` = new edges matched afterwards, = `edges` normally; `trigger` = the CHECK's why (demand / low; `-` for dev jobs); `locked` = edges sent roadDevelopmentLocked: arm / rim streets of shaped towns) | `balance` drops by about `cost` (the player is set and charged); since rev 2 a `REFUND kind=build` line follows and books it back |
| `FAILED town=… ok=false …` / `why=timeout` | always | silent refusals (water) show here with `msgs=` empty |
| `FILL town=… kind=dose\|metro why=… points=… initial=now/base near=… far=… at=x:y/…` | **always**, before the DevelopAt calls after a build (shaped towns: dose; metropolis towns: metro); v8: the calls go out back to back, the debug `FILL … sent= ok= timeouts= concurrent=true` line after all answered | `FILL … skip=cap\|surge\|metroMax` (debug) when a fill is left out |
| `FILL restore town=… initials=before->afterDevelopAt->restored base=…` | **always**, after a dose's or (v8) a metropolis fill's DevelopAt calls when they raised the initial capacities (metropolis: at most +25 % per fill) | the middle value ≈ the town's capacity = DevelopAt reset them (findings towns.md) |
| `FILL effect town=… kind=… s=… near=a->b far=a->b buildings=a->b cap=… initial=a->b sizeFactors=…` | debug, the town's next check after a fill | where the growth went (60 m / 200 m around the points); `initial` should stay restored |
| `GROW town=… sizeFactors=… to=…` | testing param on | |
| `LEVELS town=… action=set\|clear why=sparse\|change\|dense pb=… k=… was=… weights=a/b/c/d\|default lvl=a:…,u:…,w:…,c:…` | always (a world change; skips debug, once per reason) | new maps only; k 0.25-1 by how far persons per building are below 4.5; never on a town with a player's own weights (`skip=player`); 2026-10-14 late |
| `TICKCOST s=… ticks=… avgUs=… maxUs=… at=… getMaxUs=… getAvgUs=… over4ms=… over16ms=… over50ms=… pvB=… pvN=…` | always, every 300 real s while the mod runs (2026-10-14; getAvgUs, pvB, pvN 2026-10-20) | the GUI tick's cost (state:get() + Driver:tick); `at` = the slowest tick's stage (chars / names:<phase> / job:<stage> / idle); `getMaxUs` / `getAvgUs` = the slowest / mean saved-state copy; `pvB` / `pvN` = the provenance record's chars (cap 32768) / entries |
| `NAMES words … towns=… assignMs=…` | always, once per new map | the names assign runs in one tick: its cost in ms (offline 40-100 ms at 30-60 towns) |
| `ERROR stage=… err=…` | always | report every one |

## 1. US map, new game (the main test)

1. Settings: Organic Towns **Act on: New towns only** (default), **Debug log: On** (the "Testing: grow towns faster" setting
   these steps used is gone since rev 3: grow with the dev tools' Simulate natural growth),
   lookahead Medium. Name set **USA** (or any `square_names_us_*`), temperate, start year 1960 (`town_new_*`
   templates) — repeat once with 1900 (`town_old_*`).
2. Start the game, let it run at speed 4.
3. Expect within ~5 s: `INIT on=true region=US profile=NA_GRID`, `SAVE event=init … fresh=true known=0`, `RUN`.
   - [ ] `INIT` shows `nameList=` with the USA path (not `nil`). If `nil`: runFn's global did not reach
     guiUpdate; report the INIT line.
   - [ ] `fresh=true` on a new map. If `false`: the fresh-map test (`GAME_TIME.gameTime` < 120 s, `ot_saved.FRESH_GAME_TIME`)
     is wrong; report the `gameTime=` value.
4. Watch `CHECK` lines; with Testing on, towns grow by a quarter every 40 s (`GROW`). Once a town's `open` falls
   under `need` (`why=low`): `PLAN` → `SEND` → `BUILT`. Fresh towns should fire within the first minute (the
   first run's rule never fired: PLAN.md 6.2 "Trigger"). Report a few CHECK lines either way (tuning).
   - [ ] First `BUILT ok=true`. Find the town (name in the line), screenshot the new streets.
   - [ ] The new streets are a straight grid continuing the town's own street direction, joined at the town's dead
     ends; **no red dead-end sign** at the joint nodes.
   - [ ] `balance` unchanged (or report the drop and whether it equals `cost`).
   - [ ] Template: 1960 game → new-style town streets; 1900 game → old style.
   - [ ] No stray streets across water, rail or other towns' streets; no demolished buildings.
5. Keep running 10–20 minutes (speed 4–8, Testing on):
   - [ ] Houses appear along the new streets (adoption can take a while; it starts at the joints).
   - [ ] Later increments continue the same grid (no rotated or shifted second grid). `STYLE … axisSource=saved`.
   - [ ] Frame rate: no noticeable hitch every 3 s. `CHECK … us=` and `PLAN … us=` stay below ~10 000 µs; report
     the largest.
   - [ ] Count `SEND` vs `BUILT ok=true` vs `FAILED`; report `REFUSED` reasons.
6. Save, quit to menu, reload:
   - [ ] `INIT`, then `RUN actOn=new knownTowns=0` (no new `SAVE event=init`), growth continues on the same grid.

## 2. Existing save (add to save)

1. Load an existing US-names save **without** the mod. Save a backup. Enable the mod (defaults), load.
2. - [ ] `SAVE event=init fresh=false known=<number of towns>`, then `RUN knownTowns=N`, then only `SKIP …
     reason=existingTown` (debug) and **no** `SEND`. Existing towns are left alone.
3. Quit, set **Act on: All towns**, load the same save:
   - [ ] Existing towns now get increments (`SEND` / `BUILT`), joined at their dead ends.
4. A European-names save with **Street style: Automatic**: `INIT on=false reason=style`, nothing else. With
   **Street style: North American grid**: towns grow grids.

## 3. Remove from save

1. Take a save from test 1 or 2 that has several mod-built increments. Quit to the **main menu** (never remove a
   mod with a save loaded: "cannot remove mods in game").
2. Disable Organic Towns (Warning dialog expected: severityRemove Warning), load the save.
   - [ ] Loads without errors; the mod's streets are still there as plain town streets; towns keep growing on
     them; no `[SQOT]` lines; no Lua errors mentioning `organic_towns` in stdout.txt.
3. Re-enable and load: `RUN` again, the saved frames are reused (`axisSource=saved`).

## 4. Edge cases (report what happens)

- [ ] A town by a river or the coast: no street touches the water (`FAILED` with empty `msgs` would mean the
  engine refused a wet street; the pieces are then left out).
- [ ] A hilly town: no street steeper than ~12 %; increments stop at steep sides (`PLAN edges=0`).
- [ ] Two towns close together: increments don't join the other town's dead ends (`noJoin=otherTown`).
- [ ] Player roads and a bus stop on a dead-end street: those dead ends are never joined (`noJoin=edge`).
- [ ] Map editor: `INIT on=false reason=mapEditor`.
- [ ] Settings Off: `INIT on=false reason=param`.

## What to send back

`grep '\[SQOT\]' stdout.txt` (or the first 200 and last 200 lines), screenshots of 2–3 grown towns, and any
crash dump time. The `SEND` line right before a crash names the proposal.

## Open points this run should answer

- guiUpdate sees runFn's global and sends commands with callbacks (probe I/G say yes).
- Fresh-map detection by `gameTime`.
- ~~No player charge with a Context without `player`~~: since the crash fix the context has the player and the
  build **charged** it (balance 0 -> -537305, 2026-10-11). Whether a build without player crashes: "Build as
  player" test below.
- Template override (an edge copied from a small street with `roadTemplate`/`laneConfigs` of the large template:
  main streets) builds like a copied edge.
- Whether our own dead ends ever get a node config after adoption (they are only joined then; `noConfig` count
  in `SNAPSHOT` should drop over time if so).

## Dev tools (`square_organic_towns_dev`, DEV only, never upload)

A HUD button **OT Dev** (top-left mod buttons) opens a window to grow towns on demand, in any city type, and to
undo. It needs Organic Towns enabled: it loads the main mod's modules (`ug_require "square_organic_towns::/…"`)
and runs them in its own game script (`guiUpdate`, the Lua state where runFn's region global and command callbacks
work). The window talks to that game script with `api.gui.fireGuiScriptEvent` (commands) and hears its status
through `api.gui.fireReactEvent` (both are base-game patterns, first use in our mods).

Setup: **quit TF3 fully** (a running game keeps old Lua modules). Enable `square_organic_towns` **and**
`square_organic_towns_dev`; **disable `square_organic_towns_probe`**. Throwaway save, backups before Undo. Settings
of the main mod as in test 1 (Act on New towns only or All towns; Debug log On helps; Testing grow can stay Off:
the dev tools grow towns themselves). `make link` is done.

Log: every dev step is a `[SQOT_DEV] …` line; the dev jobs reuse the main stages, so they log `[SQOT_DEV] CHECK /
STYLE / SNAPSHOT / PLAN / SEND / BUILT / FAILED` with the same fields as `[SQOT]`. `grep 'SQOT' stdout.txt` shows
both.

First checks after loading a map:

- [ ] `[SQOT_DEV] LOAD ok=true` on the first frame. `ok=false err=…` = the cross-mod require failed: report it.
- [ ] `[SQOT_DEV] MAIN visible=true phase=run` ~3 s later (`visible=false`: see the third check).
- [ ] Open the window: the first line says **Link: ok**. "no reply" = the HUD ↔ game script events don't work:
  report it (and whether `LOAD` appeared).
- [ ] The Link line says **Main driver: visible, run** (same Lua state as the main mod's game script). "NOT
  visible" = separate states: Pause and undo of main-mod builds won't work (dev builds still do); report it.

Window layout (2026-10-12, as the Stress Test window): **at the top, always visible**, the Link line, the Main
driver line, the queue (`Task: … (+N queued)`) with **Stop dev tasks** and **Pause / Resume main driver** (plus
**Stop simulation** / **Stop tour** while one runs), and the Simulation / Showcase / Tour progress lines (the tour's
town label large). Below, five **tabs** (the selected one is remembered for the session): **Simulate** (Simulate
natural growth, Game speed 4x, Tour all towns), **Showcase** (build all, next-showcase options, settle, Auto tour /
Previous / Next town, reset, progress and results), **Town** (pick / inspect, city type, Grow now and the other
selected-town tools, roundabouts and node dump), **Main mod** (driver, debug log, build as player, Fast-forward all,
Grow all towns), **Camera & tour** (both tours, screenshots, views, seconds per view, camera distance, top-down).
The log is under the tabs. Each section's main action sits at the right of its heading; green = the "go" action,
red = stop / confirm, amber = destructive or unverified. On/off options are check boxes.

| Control (tab) | What it does | Expect in the log |

|------|---|
| Pick town nearest the camera / Refresh (Town) | selects the town closest to the camera centre and shows the inspector: buildings, extent r, edges, lots (built, free, gaps, open frontage, virtual), capacity cur/target and sizeFactors, **Needs room** and why, the main mod's style (profile, outer zone, axis and its source), the picked style, joinable dead ends (and why others aren't), the saved grid frame, increments built this session (main / dev / undoable), map region / profile / nameList / climate | `SELECT`, `INSPECT town=… open=… need=… needsRoom=… why=… style=… joinable=…` |
| City type picker (Town) | city type for Grow now / Plan only: **Main mod (auto)** (what the mod builds: NA grid, suburbs outside 500 m from 1950), **Region (auto)** (the profile the map's names/climate pick, any style), or one of the 9 profiles (NA grid, NA suburb, EU organic, EU extension, MED hill, MED ensanche, JP dense, Nordic, Superblock; each with its era's outer zone, climate and terrain modifiers) | `STYLE town=… mode=… style=…` on the next job |
| Increments 1/3/5/10, Growth x1.25/1.5/2/3 (Town; Growth also in Main mod) | pickers for Grow now and the growth buttons | |
| **Grow now** (Town) | N times: plan + build the next increment in the picked style now (needs-room test ignored), then forced growth: `makeTownUpdateSizeCmd` with sizeFactors x Growth, then 2 more passes at the reached size, 4 s apart | `QUEUE`, `START`, `CHECK … force=true`, `PLAN`, `SEND`, `BUILT`, `STEP … increment=k/N outcome=built style=…`, 3 x `GROW`, …, `DONE … result=done` |
| **Plan only (dry run)** (Town) | plans and pre-checks the next increment in the picked style, never builds: every edge logged, green leaf icons along the planned streets for 30 s; **Show plan again** re-spawns them | `DIAG …` (failing edges) + `DIAGSUM …`, `DRY town=… spec=… preCost=…`, `PLANEDGE i=… from=x,y,z to=x,y,z class=… template=… join=…`, `MARKERS icons=…` |
| **Undo last increment** (Town; click twice within 8 s) | removes the streets of the town's newest increment built this session (main mod's or dev): orphan nodes removed, the joint's lane config pruned back to a dead end (only nodes that have a config). Refused when an edge is player owned or has a stop, or a node has traffic lights. **Houses on those streets are demolished** (HANDOFF D4) | `UNDO town=… edges=… nodesRemove=… cfgPrune=… builtLots=… warn=…` (before sending), then `UNDONE` or `UNDO … ok=false` |
| Grow town only (Town) | forced growth of the selected town (3 passes), no streets | `GROW` x3 |
| Join own dead ends check box (Town) | dev builds only. Off = as the main mod: dead ends of our own unadopted streets (no lane config) are never joined, so **Grow now with N > 1 may stop after one increment** (`SNAPSHOT … noJoin=noConfig:k`, `STEP … outcome=empty`) until the town adopts them. On: they are joined and a lane config is added to the script node. **Unverified** (backup save; watch for a crash and report the `SEND` line before it) | `OWNJOINS on=…` |
| Rounds 1/3/5/10, **Fast-forward all** (Main mod) | M rounds over every town the main mod acts on (New towns only: towns not known at first sight): one forced growth pass (Growth factor), then the main mod's normal check **with its trigger**, building when it fires; no 3 s spacing | `FAST rounds=… towns=…`, per town `GROW` + `CHECK … force=false` (+ `PLAN/SEND/BUILT` when `why=low`), `ROUND round=… built=…` |
| Grow all towns (Main mod) | one forced growth pass for every acted-on town, no streets | `GROW` per town |
| Pause / Resume main driver (top; also Main mod) | the main mod starts no new check and no testing growth (a running build finishes); session only | `PAUSE paused=… mainVisible=…`; no `[SQOT] CHECK` lines while paused |
| Debug log: Mod setting / On / Off (Main mod) | overrides the main mod's Debug log setting for this session | `DEBUG mode=…`; `[SQOT] CHECK` lines appear / stop |
| Stop dev tasks (top) | drops queued tasks; the running one stops after its current step | `STOP dropped=…`, `DONE … result=stopped` |
| **Simulate natural growth** (Simulate tab; Stop simulation there and at the top) | grows towns as the game would if they were connected, on any map with no transport (`otd_simgrow.lua`): each town gets a seeded connectedness (25 % none, most slow, ~12 % fast, ~4 % metropolis candidates; "Big towns better connected" biases it), its simulated experience follows the game's level curve, and the game's own target / district split (`docs/findings/towns.md` "Natural town growth") is applied with `makeTownUpdateSizeCmd(town, sizeFactors, false)` in quarter-year steps: no forced building update, the houses come at the game's pace. Not a task: the main driver keeps running with its needs-room trigger. Pickers: real s per simulated year **0 (as fast as possible)** / 1 / **2** / 5 / 10 / 30 / 60 (counts only while the game runs; changeable while running), Fill every 1 / **2** / 4 / 8 years (tooltips: 8 about twice as fast as 4, coarser), seed 1-5, stop after never / 20 / 40 / 60 years; Towns: all / near camera (4 km); Tour all towns when stopped, Move the game date with the simulated years (on by default since NEXT_PHASE_BRIEF 68; forward only, `SIMGROW date`) (check boxes); **Quick: 40 years** (pace 0, fill every 4) and **Build out: 100 years** (10 chunks of 10 years, every town, the tour; for judging mature towns: `SIMGROW chunk` lines); Game speed 4x. Session only: Start again (same seed) resumes; after a reload each town's experience is derived from its current size. **Changes the towns for good** | `SIMGROW start seed= pace= scope= towns= none= slow= medium= fast= minWeight= mainPaused=`, one `SIMGROW town` per town at start (rate, class, level, factor, sizeFactors, buildings), per simulated year one `SIMGROW town year= ... level= factor= target= persons= added= weights= to= buildings=` per grown town and `SIMGROW year year= growing= applied= buildings=N(+k) top=name:buildings:xfactor:rrate,...`; at the end one `SIMGROW final ... factor=a->b buildings=a->b` per town and `SIMGROW stop reason=button\|limit` (+ `ALLTOWN` lines and `TOUR auto source=simgrow` with the tour) |
| Build as player check box (Main mod) | every build (main mod and dev) with or without the player in its context; ON (default, every load) is the known crash-free setting and charges the player; off = crash bisect (backup first) | `PLAYER on=…`; `SEND … player=on\|off` |

While a dev task is queued or running, the main driver is held automatically (no races; one command in flight),
and a dev task waits until the main driver has finished its own job.

Suggested runs:

1. US map, 1960, a fresh small town: Pick → read the inspector (Needs room should be YES or close; note `open` vs
   `need`) → Plan only (Main mod) → look at the leaf markers → Grow now N=1 → screenshot → Undo → the streets are
   gone, the joint shows no red dead-end sign → Grow now N=3.
2. Same town or a neighbour: each style once with Plan only, then Grow now N=1 for EU organic, MED hill, JP dense
   and Superblock (Undo in between, or a different town each). Screenshot each.
3. Pause main driver, then Fast-forward all, 3 rounds, Growth x1.5: count `BUILT` per round, report CHECK lines of
   towns that didn't build (`why=open`: their open frontage and need).
4. Report every `ERROR`, `FAILED`, `REFUSED` and `UNDO … ok=false` line.

## Curved styles, per-edge diagnosis and the player test (2026-10-11, after the EU organic refusals)

**What changed.** Every EU organic increment was refused by the pre-check (`Construction_Not_Possible`, even 3
edges). Offline the new checker (`ot_check`) found the cause: curved edges far tighter than the town street
templates allow (`minCurveRadius` 44 m for a final proposal, 60 m with the player's tool): 43 of 240 EU organic
edges on flat land below 70 m, the worst 6 m (a 10 m ring piece whose end tangent was 24 deg off its chord).
The plan lines are now smooth curves of at least 80 m (spokes steer at most 10 m / 90 m per step, ring arcs are
polar curves square to the spokes, bent lanes are filleted), edges carry the curve's exact tangent at each node
(one tangent per node along a street) with the arc length as magnitude, and the planner drops a piece whose edge
would stay under 70 m (`dropped=curve:N` on PLAN lines). Jittered grids (JP dense, Nordic, NA suburb) give their
lattice lines one tangent through each node where it fits. Every profile's simulated edges now pass (PLAN.md 6.2
"Curves").

Setup as "Dev tools" above (the dev mod turns the diagnosis on for the main driver too). Debug log On.

1. **Each curved style, Plan only first.** A 1960 map (any names), pick a small town, style **EU organic** →
   Plan only. Expect `[SQOT_DEV] PLAN … minR=…` ≥ 70 and `geoBad=none`, then `DIAGSUM … whole=ok failed=0`
   and `DRY`. Then Grow now N=1. Repeat (Undo or another town) for **EU extension, MED hill, NA suburb, JP dense,
   Nordic**, and **NA grid** as the control. Per style report: `PLAN` (minR, edges), `DIAGSUM`, `DRY`/`REFUSED`
   msgs, `BUILT`, a screenshot.
   - [ ] EU organic builds (`BUILT ok=true`). If still `REFUSED … Construction_Not_Possible`: send the `DIAG`
     lines (which edges fail alone, their `len`, `minR`, `dev`, `join`) and the `DIAGSUM` line.
   - [ ] `DIAGSUM failed=0` while the whole increment is refused: the cause is not one edge (the joints, two new
     edges crossing an existing street's area, the town around it): report it with a screenshot of the markers
     (Show plan again).
   - [ ] On a hillside town (MED hill): no street steeper than ~12 %, spokes wind along the slope.
2. **Build as player** (Main mod driver section; default **ON**). Today every build charges the player
   (`BUILT … balance=a->b` drops by `cost`). The BaseNodeConfig crash (findings 2026-10-11, last bullet) had
   two differences from working builds: no player in the context, and no configs on the new nodes. Configs on
   new nodes are now always on, so the player is the only variable left. **Backup save first.**
   - [ ] Toggle to **off** (`[SQOT_DEV] PLAYER on=false`), Grow now N=1 on NA grid (known to build).
     `SEND … player=off` must be the line before the build.
   - [ ] No crash: report the `BUILT … balance=a->b` (unchanged balance = the town pays; then main mod default
     can go off). Crash: report the time and the `SEND` line; the cause was the player, keep it on.
   - [ ] Toggle back ON before other tests (it resets to ON with every load).
3. Report every `DIAG`, `DIAGSUM`, `REFUSED`, `FAILED`, `ERROR` line.


## Showcase (2026-10-11): every style side by side on Blank Slate

**What it is.** One button in the dev window, **Showcase: build all**, lays out and spawns one town per style
(NA grid, NA suburb, EU organic, EU extension, MED hill, MED ensanche, JP dense, Nordic, Superblock), an NA grid
town on the old templates ("NA grid old", 1940+ games), two vanilla control towns ("Control A", "Control B": no
mod streets, the same forced growth) and a Probe C row of vanilla towns with `initialMajorStreetAngle` 0 / 15 /
45 / 90 ("Vanilla angle 0" ...), then grows them all unattended: round-robin, each turn a forced increment in the
town's own style (pure profile, no outer zone) followed by two forced growth passes to sizeFactors 1 + step x
0.25 (every town, controls too, on the same schedule). It also uses the new **irregular growth** (PLAN.md 6.2):
towns should no longer grow as even rings. Details: `otd_showcase.lua`, `otd_layout.lua` headers.

**Unverified in game** (first run answers them): `createTowns` / `makeTownCreateCmd` from the dev game script's
guiUpdate (the Stress Test sent them from a GUI plugin state), the TownInfo angle units (degrees assumed, as
`townMajorStreetAngleRange`; the CREATE line logs what createTowns gave), `setCameraData` for Next/Previous town
(and which pitch is top-down), curved styles building in game (ot_check passes offline), and adoption of our
script dead ends between increments.

Setup:

1. **Map:** Main menu → Map Editor → new map, temperate, **Normal or Large size** (the island needs room: on a
   small map Probe C and the controls are dropped first, logged as `SHOWCASE DROP`). Generate heightmap →
   **Blank Slate (flat island)** → save → **Play Map**. Start year **1960** (new templates; the era town compares
   old vs new; before 1940 there is no era town). Name set any (the showcase forces each style). Money: the
   builds charge the player ~0.3-0.5M per increment, about 10 style towns x N increments: with N = 40 roughly
   150-200M. Pick the easiest difficulty / most starting money (sandbox or a "no costs" option if the start menu
   offers one); the balance may go negative (it did in the first runs without blocking builds).
2. **Mods:** `square_organic_towns` + `square_organic_towns_dev` + `square_blank_slate`; **disable
   `square_organic_towns_probe`** and every other town/street mod. Organic Towns settings: defaults are fine
   (Debug log On helps). `make link` is done. Quit TF3 fully after any code change.
3. Load the map, let it run at speed 1-4 (commands need a running game). Open **OT Dev**: the first line must
   say `Link: ok`.

Run:

1. Section **Showcase**: Increments per town **10** for the first run (about 20-30 min), later 20 or 40
   (40: ~1.5-2 h). Press **Showcase: build all**. The main driver is paused at once and **stays paused** (Resume
   button in "Main mod driver"; a reload resets it), otherwise it would grow the new towns as NA grids.
2. Watch the window: the head line (phase, towns created, increments built, towns still growing, turn) and one
   line per town (step k/N, built, refused, empty, stop reason). Everything is also in stdout.txt:
   `grep 'SQOT_DEV] SHOWCASE' stdout.txt`.
3. **Stop** ends it after the current step and logs the numbers so far; **Showcase: build all** again resumes
   (also with a larger N). After a reload the towns are found again by their names (no duplicates; their step
   counts start at 0). **Forget showcase** drops the state (not the towns).
4. A town stops on its own after 3 refused builds or 4 empty plans in a row (`SHOWCASE STOP … why=…`). Empty
   plans with `noJoinableDeadEnd:noConfig` mean the town hasn't adopted our last increment's dead ends yet. If
   most style towns stop that way, run again with **Join own dead ends: ON** (unverified in game: backup save
   first; the SEND line before a crash names the proposal).

Expected log, in order:

| Line | Check |
|---|---|
| `SHOWCASE START n=… resume=… mainPaused=true ownJoins=… player=…` | |
| `SHOWCASE ISLAND box=… land=minX,minY,maxX,maxY width=… height=…` | the island measured with isOnWater from the map centre; report it |
| `SHOWCASE LAYOUT towns=16 of=16 dropped=0 spacing=… cols=… rows=… year=… era=new` | spacing 1300-2500 m |
| `SHOWCASE PLACE key=… label=… x=… y=… angle=… templates=… coast=…` x16 | NORDIC: `coast=420m_<side>` (moved to the shore: its grid axis follows it) |
| `SHOWCASE DROP key=… why=space\|water:…` | only on small maps |
| `SHOWCASE CREATE key=… angle=… angleSet=true givenAngle=… givenInitAngle=… givenCaps=… ok=true` | `ok=false err=…`: createTowns failed in this state, **report it** (nothing else will work) |
| `SHOWCASE CREATED key=… town=… name=… ms=…` (+ `RENAME`) | one town at a time |
| `SHOWCASE STEP key=… step=k/N outcome=built\|empty\|fail\|growth built=… refused=… empty=… cost=… why=…` | one per turn; `growth` = vanilla towns |
| `[SQOT_DEV] SEND / BUILT / REFUSED / DIAG / DIAGSUM` | as in "Dev tools" and "Curved styles" |
| `SHOWCASE STOP key=… why=refused x3: …\|empty x4: …` | report every one |
| `SHOWCASE TOWN key=… steps=… built=… refused=… empty=… cost=… buildings=… edges=… r=… shape=drift=…_spread=…_cv=…_elong=…` | at the end (and on Stop) |
| `SHOWCASE SUMMARY towns=… turns=… built=… refused=… empty=… stopped=… cost=… minutes=…` | the whole run in one line |

Screenshots (after the run; the game can be paused):

1. Press **Next town**: the camera jumps to the first town at 1800 m distance with the angle/pitch the camera
   had at the first jump (set a nice oblique view first, or toggle **Top-down: ON**; **Reset camera angle**
   takes the current one again). The window shows the town's label, steps, buildings, edges, refusals and
   shape numbers (`SHOWCASE FOCUS` line in the log). A `[SQOT_DEV] CAMERA … asked=… read=…` line 1.5 s later
   says whether the camera kept the distance and pitch: report a few.
   - [ ] **Each town: one overview** (whole town in frame), named by its label. 16 screenshots.
   - [ ] **Each style town: one close-up of a joint** (where a mod street meets an engine street): red dead-end
     sign or not.
   - [ ] If Top-down works (`read=` pitch equals the asked one and the view is straight down): one top-down
     shot per style town as well.
2. What to look for:
   - Styles: NA grid straight and axis-aligned; NA suburb bent streets and cul-de-sacs; EU organic radial spokes
     and rings; EU extension wider rings; MED hill tight lanes; MED ensanche square blocks; JP dense small blocks;
     Nordic along the shore; Superblock huge blocks.
   - **Irregular growth:** towns lopsided / lobed / with ribbons along their main streets instead of round
     rings (offline numbers: PLAN.md 6.2 "Irregular growth"; compare with the `shape=` values in the TOWN lines).
   - Houses on the mod's streets (adoption) vs empty streets.
   - Probe C: does the angle change the vanilla street pattern (0 vs 15 vs 45 vs 90)? Controls vs mod towns:
     same growth schedule, how different do they look?
   - Era: "NA grid old" vs "NA grid": old vs new street templates (its joint edges copy the town's own street,
     so they stay new).
3. Send back: `grep 'SQOT' stdout.txt`, the screenshots, every `STOP`, `FAILED`, `ERROR`, `CAMERA` line, and a
   crash dump time if any.

## Showcase v2 (2026-10-11, after the first showcase run)

**What changed since the first run** (details: PLAN.md 6.2 "Showcase v2"):

- Lane assertion (`lane_config_util.cpp:364 GetLaneOffset … Actual: 6 >= 4`, 105 times): every junction config
  now uses each street's own lane count and is checked before sending (`laneIndex:` refusal instead of an engine
  assertion). It was the `Construction_Not_Possible, collisions=0` refusals, including JP dense's stop.
- A refused pre-check no longer halves the plan at once: every edge is pre-checked alone, the ones that fail are
  dropped and the increment is planned again at full size (twice), only then halved. Leftovers under 3 edges that
  close no loop aren't built (`TINY`). The planner keeps 16 m (20 m for main streets) between a new edge and the
  existing streets it doesn't meet, so fewer `Collision` refusals.
- Per-edge diagnosis works now (`DIAG … partners=edge<id>:<size>@<m>`): the old check looked for
  "Construction_Not_Possible" with underscores, but the engine's message has spaces.
- Narrower streets: a planned main street is now `medium` (was `large`), collector and minor streets `small`;
  MED hill / JP dense: `small` / `small` / `xsmall`.
- Leads: a main street goes at most one piece beyond the town's streets, small streets two (no more 300-800 m
  empty stubs).
- Rounds are faster: all style towns build one after the other, then the growth passes for all towns go out as
  one batch. Expected round time with 18 towns: about 6-10 s (the first run took ~80 s, of which ~65 s were pauses).
  Each round logs `SHOWCASE ROUND round=… s=…`. Please report a few.
- Era row: "NA grid 1900" and "EU extension 1900" (old templates) next to the map-era style towns. There is no
  1960 column: only the plain town templates differ by era (old/new from 1940), so 1960 builds exactly like 2020.
- Roundabout town "EU ext roundabout" (only with Roundabouts & Interchanges enabled), plus the dev button
  **Roundabout here**.
- Window: the **Results** table after a run, **Auto tour** (+ screenshots), **Reset showcase**, and two probe
  toggles: **Fill mod streets** and **Freeze style towns**.

Setup:

1. Map: Blank Slate as before (Normal or Large). **Any start year from 1940 on** works (the era row compares with
   1900 by itself); 2020 is fine.
2. Mods: `square_organic_towns` + `square_organic_towns_dev` + `square_blank_slate` + **Sandbox mod** (money; the
   builds charge the player) + optionally **Roundabouts & Interchanges** (`square_roundabouts`) for the
   roundabout town. Disable the probe mod and other town/street mods. **Quit TF3 fully** first (old modules stay
   loaded). `make link` is done.
3. Load, speed 1-4, open **OT Dev**: `Link: ok`. The log has `[SQOT_DEV] ROUNDABOUTS available=true|false why=…`.

Run 1 (default options):

1. Showcase: N = **10** (or 20) → **Showcase: build all**. 18 towns with Roundabouts, 17 without.
2. Watch the head line (round, last round's seconds). When it ends, the **Results** section lists per town: steps,
   built/refused/empty, edges (mod edges, how many of them have lots), buildings (houses on mod streets), shape.
3. **Auto tour**: pick 5/10/20 s per view, **Screenshots: ON**, **Views: overview + top-down** if wanted, press
   **Auto tour**. The camera visits every town; the label shows large in the window; one screenshot per view.
   The game names the screenshot files itself: the log lists them in order (`SHOT n=… town=… view=…`). Please
   tell us where the files landed (userdata folder) and whether the window shows in them.
4. Close-ups as before: a joint, and the roundabout (ring, arms, houses?).

Run 2 (probes, same map): **Reset showcase (destroy towns)** (click twice). Log: `SHOWCASE DESTROYED town=…
edgesBefore=… edgesAfter=… townExists=…` per town and `SHOWCASE RESET … edgesLeft=… nextOffset=…`. If streets
stay, the next layout moves by 1250 m by itself. Then toggle **Fill mod streets: ON** and/or **Freeze style
towns: ON** and build again (N = 10).

Expected log, new or changed lines:

| Line | Check |
|---|---|
| `SHOWCASE START … fill=… freeze=… ring=… diagnose=true` | |
| `SHOWCASE PLACE … era=2020:new` / `era=1900:old` / `vanilla:2020` | |
| `[SQOT_DEV] PLAN … pruned=k`, `PRUNE town=… dropped=… pieces=…`, `TINY …` | dropping instead of halving |
| `[SQOT_DEV] REFUSED … partners=…`, `DIAG … partners=edge123:small@9` | what a plan collided with (existing street, its size, metres from our edge) |
| `[SQOT_DEV] GROW … batch=18` | growth as one batch |
| `SHOWCASE STEP … edges=… mod=… vanilla=… buildings=…` | new edges per round: ours vs the town's own |
| `SHOWCASE FILL key=… points=…` (Fill on) | then compare `adoption=` in the TOWN lines |
| `SHOWCASE FREEZE key=… active=false ok=…` (Freeze on) | does `vanilla=` stay 0 for style towns? |
| `SHOWCASE RB PLAN … size=XS|S|M ok=… msgs=… partners=…`, `RB SEND … newNodeConfigs=none`, `RB BUILT … ring=4 arms=4 cost=…` | roundabout town at step 3 |
| `SHOWCASE RB ADOPT … ring=a/b_edges_with_parcels_…_built arms=…` | every round after: does the town adopt the ring and arms? |
| `SHOWCASE ROUND round=… towns=… s=…` | round time |
| `SHOWCASE TOWN … era=… modEdges=… adoption=…_edges_with_parcels_…_lots_…_built roundabout=…` | |
| `SHOWCASE SUMMARY … modEdges=… adopted=… modHouses=… prunes=… tiny=… roundS=… notPossibleNoCollision=…` | `grep -c lane_config_util stdout.txt` should be 0 now |
| `[SQOT_DEV] TOUR …`, `SHOT n=… town=… view=… ok=…`, `CAMERA … asked=… read=…` | |

Roundabout here (any town with a free dead end): point the camera at a town's dead end at its edge, **Roundabout
here**. Log `RB PLAN` (per size tried), `RB SEND`, `RB BUILT` or `RB … ok=false why=…`. Toggle **Ring: two-way town
street** to try a ring the town may line with houses. Later **Roundabout adoption** logs `RB ADOPT`. Report: does
it build, a red dead-end sign anywhere, do cars drive through it (config-less ring nodes), houses on ring/arms.

Send back: `grep 'SQOT' stdout.txt`, `grep -c lane_config_util stdout.txt`, the screenshots, and what you see.

## Showcase v3 (2026-10-11, after the settled showcase and the roundabout crash)

**What changed** (dev mod; main-mod planner changes: PLAN.md 6.3):

- **Roundabout crash fix.** Every new roundabout node gets a node config now (the config-less ring crashed on the
  3rd "Roundabout here", Engine.h:323 BaseNodeConfig). Two-way ring (the default now): the engine pattern at each
  ring node over ring in, ring out and the arm; free arm ends an empty config. One-way ring: a pattern derived
  from the lane rules (ring in -> ring out on both lanes, ring in -> arm, arm -> ring), **not verified**, so it
  only builds with **One-way ring: experimental ON**; without it a one-way roundabout is refused
  (`why=oneWayExperimentalOff`) and the showcase roundabout town uses the two-way ring. `RB SEND` logs
  `newNodeConfigs=7/7 ring=town|oneway`.
- **Node dump** button (Town section): logs the street nodes within 60 m of the camera, each lane connection with
  its meaning (which end of the edge the node is, edge lane, forward flag, in/out) and our derived pattern for the
  same node. Read-only.
- **Shape row** (8 EU extension towns, "Shape: compact / linear / cross / fingers / fan / twin / lens / ridge")
  and **Density row** (4 EU extension towns: "Density: weights" = per-town level weights from the style profile,
  "Density: upgrade" = DevelopAt with upgrade buildings at the centre every round, "Density: medium streets" =
  every planned street medium, "Density: control"). Toggles: Shape row / Density row (default ON). With both rows
  the showcase has 29 towns (30 with Roundabouts); a small island drops Probe C first, then the density row,
  then shapes.
- **Settle phase** after the rounds: picker "Settle after the rounds, game months" off / 2 / 5 / 10 (default 2).
  Speed 4 (the game bar's fastest; `makeGameSetSpeedCmd`), waits until that many calendar months passed (max 120 s
  real per month, then `timedOut=true`), restores the previous speed, logs sizes before/after per town and the mod
  streets' adoption, then the report (TOWN / SUMMARY lines are after the settle). **Tour after settle** (default
  ON) starts the Auto tour by itself.
- **Auto tour**: the screenshot is taken once the camera reads back the target (x/y within 2 m, distance within
  2 %, two steps in a row), or after max(1.5 s, 0.9 x dwell); the tour never moves on before the shot. `SHOT` logs
  `settleMs` and `fallback`.
- TOWN lines: the shape metrics field is now `metrics=drift_…`; `shape=<id>`, `shapeAsked=`, `shapeWhy=`, `lever=`
  are new (also in STEP lines).

**Main-mod planner changes in this build** (PLAN.md 6.2 "After the settled showcase" and 6.3 "Town shapes"):

- **Town shapes.** Every town gets a shape archetype that steers where it grows (not how its streets look):
  compact, linear (street village / valley / coastal strip), cross (3-4 corridors), fingers (one corridor per
  spoke, green wedges between), fan (half-circle opening away from a coast or downhill), twin (a second core
  500-900 m out, reached by a corridor), lens (an oval around a green), ridge (long along a crest). On real maps
  the site and roads pick it (valley, crest, coast, river, hillside, country roads leaving the town, a neighbour
  town, a station); on Blank Slate (flat) each town draws one from its style's weights plus its context: the
  showcase towns stand 1.3-2.5 km apart, so "toward the neighbour town" (linear) and, under 1.8 km, "growing
  together" (twin) will show up, as will roads the game builds between them. The STYLE line logs `shape=<id> shapeWhy=<reason> shapeGeom=<id>_axis=<deg>_arms=<deg/deg/...>`; PLAN
  lines carry `shape=`. The shape is saved with the town's plan frame at its first build (reloads keep it).
- **No self-collisions.** New edges of one plan keep clear of each other (crossing, running alongside, an end
  node on another new street; 16 / 20 / 24 m by street width). PLAN lines log `self=0` (the number of
  self-conflicts left; always 0 offline).
- **Combination refusals.** When the whole plan is refused but every edge passes alone ("Construction Not
  Possible" with no collision, 46 in the last run), each junction (a node with its new edges) is pre-checked:
  `DIAGNODE town=… node=… edges=… keys=… classes=… minAngle=… shortest=… msgs=…`, then the newest edge of each
  failing junction is dropped and the plan redone at the same size (`PRUNE … by=star`), instead of halving.
  `DIAGSUM` gains `stars= starsFailed=`. Please send these lines: they tell what the engine dislikes at our
  junctions.
- **Look rules.** No zig-zag chains (three corners in a row turning left / right) and no loops hanging off the
  town on a stem; the planner checks the built result and re-plans. Offline over 7 styles x 3 towns x 12
  increments from a vanilla core: 0 chains and 1 lasso in 21 towns (without the rules: up to 6 chains and 2
  lassos per style), with as much or more growth.
- **Vanilla town street angles** (new main-mod setting, default Automatic): on a **new** EU map the starting towns
  should look less grid-like. Check `grep 'SQOT\] ANGLE' stdout.txt` right after creating the map: `region=EU
  regionSource=nameList angle=0/0->35/35`. Unverified: whether the new-map generator reads it (a fresh EU map's
  towns at diagonal angles would say yes).

What to look at in the shape row (EU extension, 6 spokes; offline metrics after 14 increments from a vanilla
core, mean of 4 towns, compact for comparison: elong 1.4, arms ~2, side 0.6): **linear** long and narrow
(elong ~2.6), **ridge** the same on flat land (~2.3), **cross** a Y of three corridors (arms ~3), **fingers** six
corridors with gaps between (arms 3+), **fan** everything on one side (side ~0.77), **twin** a lobe growing toward
the second core (drift ~0.5), **lens** an oval (elong ~1.6-1.8). The style towns show their seeded shapes (STEP /
TOWN `shape=`). Report which shapes read as intended in the screenshots and which don't.

Setup: as Showcase v2 (Blank Slate, Large if possible: 29-30 towns want ~18 km of land at 2.5 km spacing; Normal
works with tighter spacing / drops). Mods: `square_organic_towns` + `square_organic_towns_dev` + Blank Slate +
Sandbox mod + **Roundabouts & Interchanges**. Quit TF3 fully first. Load a fresh map; `make link` is done.

Run:

1. OT Dev window: check the options (Shape row ON, Density row ON, Settle 2, Tour after settle ON, Screenshots ON,
   Auto tour 1 s or 5 s). Ring stays "two-way town street", One-way ring: experimental **off**.
2. **Showcase: build all**, N = 10. Rounds run as before; then `SHOWCASE SETTLE start`, game speed jumps to 4,
   after ~2 game months `SETTLE town …` lines and `SETTLE end`, the speed returns, the report follows, and the Auto
   tour starts (`TOUR auto seq=1`). One screenshot per town; please check that the first town's shot is there.
3. Close-ups: the roundabout town's two-way ring (cars through it? houses on the ring?), a shape-row town or two.
4. **Node dump on a one-way roundabout**: build one roundabout with the Roundabouts & Interchanges tool (any town
   street, 4 arms, one-way ring), point the camera at one of its ring nodes (where an arm meets the ring), press
   **Node dump**. Send the `NODEDUMP` / `NODECONN` / `NODEOURS` lines. `NODEOURS … equal=true` would verify our
   one-way pattern; otherwise the NODECONN lines show the engine's.
5. Optional, backup save: One-way ring: experimental ON, Ring: one-way, **Roundabout here** at a free dead end.
   Then a few minutes of game time (crash?), and Node dump on one of its ring nodes.

Expected log, new or changed lines:

| Line | Check |
|---|---|
| `SHOWCASE START … ring=town oneWayExperimental=false shapeRow=true densityRow=true settleMonths=2` | |
| `SHOWCASE PLACE key=SHAPE_LINEAR … shape=linear`, `… key=DENS_WEIGHTS … lever=weights` | rows placed |
| `SHOWCASE DENSITY key=DENS_WEIGHTS lever=weights weights=a/b/c/d\|…\|… ok=true` | once, after creation |
| `SHOWCASE DENSITY key=DENS_UPGRADE lever=upgrade x=… y=…` | every round |
| `SHOWCASE STEP … shape=<id> shapeWhy=<reason> lever=…` | seeded shape of each style town |
| `SHOWCASE RB SEND … newNodeConfigs=7/7 ring=town` | no crash on later builds |
| `SHOWCASE SETTLE start months=2 mode=months calendar=… speedBefore=… speed=4` | |
| `SHOWCASE SETTLE town key=… buildings=a->b capacity=a->b edges=a->b modEdges=… adoption=…` | growth over the settle |
| `SHOWCASE SETTLE end … passed=2.0x s=… timedOut=false speedRestored=… tour=true` | |
| `[SQOT_DEV] TOUR auto seq=1`, `SHOT n=… settleMs=… fallback=false|true` | one shot per town |
| `SHOWCASE TOWN … metrics=drift_… shape=… shapeAsked=… lever=…` | |
| `NODEDUMP node=… deg=3 edges=<id>:<in|out>:L4:<template>:<lane flags> config=true conns=…` | Node dump |
| `NODECONN node=… conn=s.l>s.l from=<node0|node1>:<template>:edgeLane<k>:<F|B>:<in|out> to=… ok=true` | in -> out |
| `NODEOURS node=… ours=… match=… engine=… equal=true|false` | our pattern vs the engine's |

Send back: `grep 'SQOT' stdout.txt`, the screenshots (tools/ot_shots.py pairs them), and what you see in the
close-ups (roundabout traffic, the shape towns).

## Showcase v4 (2026-10-12, after the v3 results: site styles, wide streets, shapes, settle, refusals)

**What changed** (details PLAN.md 6.2 "Site styles, hierarchy, stronger shapes, refusals"):

- **Main mod, Street style "Automatic" acts on every map now**: each town picks its style from its site (flat open
  land: NA grid / suburb / superblock / EU extension; coast, hills, valleys: EU organic / MED hill / Nordic / JP),
  the map's region only biases, suburbs and superblocks only from 1950. Saved with the town's plan frame. STYLE
  lines: `styleSource=site styleWhy=plain:open=1.00,rough=0.00,coast=0.00,river=0,valley=0|EU|EU_EXTENSION=3.7/…
  hierarchy=late|plain`; TERRAIN lines `wideWater= wideSd= wideRange=` (2 km survey). The showcase towns keep
  their forced styles; the site styles show on a real map (step 5).
- **Wide streets** from 1950 for NA grid / NA suburb / superblock / ensanche: arterials large, collectors medium,
  local small, only on through pieces that meet another street. PLAN lines `hier=wide<n>/stub<n>/bare<n>`. A wide
  street starting at a narrower dead end takes its own template at the joint (mixed widths at that node).
- **Shapes**: stronger steering, arms lead one piece further, a growth front (no spurs into the field), a corner
  rule against saw-tooth edges (~30 % fewer corners and dead ends offline). Planning is split over ticks: PLAN
  lines `slices=`.
- **Refusals**: new planner rule `footprint` (edges too short for the junction bodies at both ends, `footprint=` on
  PLAN lines) and connectors only along the dead end's street (<= 60 deg, >= 24 m). If "Construction Not
  Possible" with no collision remains: `DIAGJOINT town=… key=conn:… len=… turn=… deadEndDeg=… edgeDeg=…
  footprint=… existingLen=… nearNode=… plain=ok|… straight=ok|… long=ok|…` (variant pre-checks of the joint edge;
  `plain` = without our joint config, `straight` = along the dead end's street, `long` = same heading, longer),
  DIAGSUM `joints=`.
- **Settle** (dev): picker off / 1 year / **2 years** / 5 years / until growth stops (plateau); "Settle at most, real
  minutes" 5 / 10 / **20** / 40; toggle "Settle: forced growth passes" (default off: every 2 game months a growth
  batch). Lines: `SETTLE start mode=years|plateau target=… capMin=… forcePasses=… clock=calendar|real`, one
  `SETTLE sample n=… calendar=… passed=… buildings=total(+delta) towns=… grew=… top=… passes=…` per game month,
  `SETTLE pass n=…` (forced passes), the `SETTLE town …` lines, `SETTLE end … reason=target|plateau|cap passed=…
  s=… samples=… passes=… buildings=a->b timedOut=…`.
- **Tour camera** (dev): "Camera distance, m" 1000 / **1800** / 2500; "Shape row: top-down" **ON** (shape-row towns
  straight down, one distance step wider). SHOT / CAMERA lines carry `key= dist= pitch= why=picked|shapeRow`;
  `TOUR start … dist= shapeTopDown=`.
- **Density: upgrade** fires once, at the town centre, at step 3 (after that round's growth): `SHOWCASE DENSITY
  key=DENS_UPGRADE lever=upgrade once=true step=3 x=… y=… ok=…`, then `DENSITY effect key=DENS_UPGRADE …
  buildings=a->b capacity=a->b`.

Setup: as Showcase v3 (Blank Slate, Large if possible; mods `square_organic_towns` + `square_organic_towns_dev`
+ Blank Slate + Sandbox + Roundabouts & Interchanges). Quit TF3 fully first; `make link` is done.

Run:

1. OT Dev window: Settle **2 years**, cap **20** min, forced passes off, Tour after settle ON, Screenshots ON,
   dwell 3 or 5 s, Camera distance 1800, Shape row top-down ON.
2. **Showcase: build all**, N = 10. Watch `PLAN … hier= footprint= slices=` and whether `REFUSED … Construction
   Not Possible … collisions=0` still appears (send the DIAGJOINT lines if so).
3. After the rounds: the settle runs (SETTLE sample lines); then the tour. Check the shape row in the top-down
   shots (linear / ridge long, cross a Y, fingers a star with gaps, fan one-sided, twin leaning to its second core)
   and the NA grid / NA suburb / superblock towns for wide arterials (only between junctions, no wide stubs).
4. Density row: the upgrade town should stay comparable to the others (DENSITY effect line).
5. **Site styles on a real map** (main mod alone, no dev mod needed): a new EU map (Europe names), Act on "New
   towns only", Debug log On, the dev tools' Simulate natural growth running (the old "Testing: grow towns
   faster" setting is gone since rev 3). After a few minutes: `grep 'SQOT\] STYLE'
   stdout.txt` should show several styles with `styleSource=site` and reasons (coast / hills / plain …). If the
   map has a coast or hills, those towns should lean to EU organic / MED hill / Nordic, flat inland towns to EU
   extension / suburb / superblock (from 1950).

Send back: `grep 'SQOT' stdout.txt`, the screenshots (tools/ot_shots.py), and what you see (shapes, wide streets,
houses on the wide streets, saw-tooth edges).

## Showcase v6: done (run 2026-10-12, session `2026-10-12_1732_sqrl-sqsg`; results and the section verbatim in HISTORY.md)

## Showcase v7: done (run 2026-10-12, session `2026-10-12_1900_sqot-dev`; results and the section verbatim in HISTORY.md)


## Showcase v8: done (run 2026-10-12, session `2026-10-12_2129_top-up-530609`; results and the section verbatim in HISTORY.md)

## Showcase v9 (2026-10-12, housed front, metropolis mechanics for the grid styles, Nordic loops, crescents)

What changed (offline, unverified in game; NEXT_PHASE_BRIEF 16, PLAN.md 6.3 "Showcase v9 round"):

- **No empty streets ahead of the houses (main mod):** NA grid, NA suburb, ensanche, superblock, Nordic and the
  polycentric metropolis plan no street farther than 1-2 blocks (`housedLead`) from a street with houses on it, so
  lattice frames and the link to a secondary centre come when the houses reach toward them. Polycentric also keeps
  its unhoused street length within 2 km (`emptyBudget`: smaller increments while the houses catch up). PLAN
  `emptyLen=m/edges` (the town's unhoused street length before the increment), `emptyCap=` (the budget's edge cap),
  `housedHeld=` (pieces held back). Offline (polycentric, 10 steps): mean unhoused length per step 9.6 -> 1.0 km.
- **Grid styles grow like a small metropolis (main mod):** NA grid, NA suburb, ensanche and superblock lock every new
  street (BUILT `locked=` = `edges=`), plan 28 edges per increment (superblock 30; PLAN `maxEdges=28`), and dose the
  fill beside any new street (FILL `kind=dose why=mech`, restored as a shaped town's dose). NA grid towns are mostly
  compact / lens (no more linear arms toward a neighbour). PLAN `gridShare=` = share of the increment's length on the
  town's grid axes. Offline from a round game-made core: steps 1-3 gridShare 0.89 (v8 settings 0.83), 27 edges at
  step 1.
- **Nordic (main mod):** curving collector loops around 190 x 150 m cells (subarctic 228 x 180), short cul-de-sacs
  from the loops into the cells (house clusters), 30 % of the cells left green, 4 meadows (1 crescent), fingers /
  linear shapes favoured, low density weights. The intended look is in PLAN.md 3 "What you should see".
- **Crescents around a green (main mod):** EU organic (2), EU extension, MED hill, Nordic (1 each) and every
  metropolis (1 park) wrap a long smooth arc of plain small streets around one of their meadows (85-130 m radius + 10 m),
  short streets meet it in T's, no streets inside, one side open. PLAN `crescents=made/planned`.
- **Dev:** the settle runs the main mod's normal check (needs-room trigger) on every style town after each grow pass
  (SETTLE end `modChecks= modBuilds=`; v8's settle grew the towns with the game's own streets only and rounded the
  shaped towns). Tour: the first shot waits 2.5 s after the tour start, every shot waits for 1 s of steady frames,
  shots >= 2.5 s apart (SHOT `steady=`). TOWN lines add `emptyLen=m/edges` (unhoused town streets), `modGrid=` (the
  mod's streets on the town's grid axes) and `crescents=`. Preview (`tools/ot_preview.py`) draws the meadows.

Setup: as v8 (NEW Blank Slate game, Large; mods `square_organic_towns` + `square_organic_towns_dev` + Blank Slate +
Sandbox + Roundabouts & Interchanges; quit TF3 fully first; `make link` is done; main mod settings: Debug log On;
Autosave off).

Run:

1. OT Dev window, **Showcase** tab: "Settle after the rounds" Settle **3 grow passes**, Tour after settle checked;
   **Camera & tour** tab: Screenshots during the tour checked, s per view **3**, Distance **1800**, Shape row:
   top-down checked.
2. **Showcase** tab: Increments per town **10**, **Showcase: build all** (green). Don't press Auto tour; it starts
   after the settle (the Tour line at the top of the window shows it).
3. When the tour has finished: `grep 'SQOT' stdout.txt` (or the whole file) and `uv run tools/ot_shots.py`.

Targets (TOWN lines unless said otherwise; v8 in brackets):

1. **Polycentric without empty streets:** Metropolis: polycentric TOWN `emptyLen` <= 2500 m and every PLAN
   `emptyLen` <= ~2500 m [no log; ~3-4 km of empty arterials in shot 32]; shot 32: no arterial grid beyond the houses
   (at most ~1-2 blocks of bare street on any side). c1 density is not a target this round (the town reaches its
   second centre only once its houses get there).
2. **NA grid grid-like from step 1:** NA grid and NA grid 1900 PLAN `gridShare` >= 0.6 at steps 1-3 (first three PLAN
   lines of each), TOWN `modGrid` >= 0.7, `orient` orth >= 0.5 [0.43 / 0.39], `shape=compact|lens` (or a site shape),
   BUILT `locked=` = `edges=`; shots 01 / 12: straight blocks along the core's edges from the first rounds.
3. **Nordic reads Nordic:** shot 09: curving loops with short dead ends into the cells, open green cells / meadows
   between the clusters, lower density than EU organic; TOWN Nordic `dens` < EU organic `dens` [12.3 vs 12.5],
   `green` gaps >= 2 [0]; `emptyLen` <= 1500 m.
4. **Crescents:** PLAN `crescents=` >= 1/1 on EU organic, EU extension, MED hill, Nordic (made / planned); in the shots
   of EU organic (03) and EU extension (04) at least one long curved street around an open meadow; TOWN `green` gaps >= 2
   on EU organic [1].
5. **Linear stays long after the settle:** Shape: linear TOWN `metrics=...elong=` >= 1.8 and `houses=` >= 1.6
   [1.22 / 1.12; during the v8 rounds 1.60-2.06 / 1.62-2.08]; SETTLE end `modBuilds=` > 0.
6. **Grid styles locked and bigger:** NA grid, NA suburb, ensanche, superblock PLAN `maxEdges=28` (superblock 30) and
   BUILT `locked=` = `edges=`; their `own=` >= 0.4 [0.32 / 0.27 / 0.27 / 0.48]; FILL `why=mech` lines on them.
7. **First shots:** `uv run tools/ot_shots.py` reports no dropped shot (shots 1-2 NA grid / NA suburb present) [both
   dropped in v7 and v8]; SHOT `steady=true`.
8. **Keep what worked:** metropolis variants as distinct as in v8 (shots 28-32; buildings 2500-5500, `own` >= 0.2);
   superblock `own` >= 0.45; Form: radiating and the shape / form rows look as in v8; Control A unchanged (vanilla);
   round time avg <= 40 s (the settle checks add ~30-60 s once); refused / DIAGJOINT / notPossibleNoCollision no worse
   than v8 (0 / 1 / 11).

Send back: `grep 'SQOT' stdout.txt`, the screenshots, and what you see (especially: Nordic, NA grid's first rounds,
polycentric's edges, crescents in EU organic / extension).

## Real map test (normal play: the main mod alone on a terrain map)

What the showcase can't show: towns on real terrain growing at the game's own pace, site-picked styles and forms,
locking in hills and valleys, neighbouring towns, metropolis towns appearing by themselves, frame time.

Setup: a NEW game on a generated **European** map with terrain: Large, hilly or mountainous relief, with a coast,
**lakes** and rivers (the generator's water settings high enough for all three; for shore towns ideally a second run on
an **island** map, an archipelago or a sea level that leaves small islands with towns), many towns, start year ~1900 so the era change
(1950: hierarchy, superblocks, metropolis polycentric) happens during the run. Mods: **`square_organic_towns` and
`square_organic_towns_dev`** (the dev mod drives the growth; don't run the showcase or any other dev tool). Main mod
settings: Act on New towns only (a new map: every town), Street style Automatic, Vanilla town street angles
Automatic, Starting town size Game size (unless running the "Starting town size test"), **Streets at industries Game default**
(the default since the final test; round 5 to the final test it was Off, which apparently dropped the roads between towns too; check `[SQOT] INDSTREETS choice=game`), Debug log **On** (the towns grow by the simulated natural growth; the 2026-10-13 run also had the testing growth
setting On, `test_grow=2` and `[SQOT] GROW` lines; that setting is gone since rev 3). Autosave as you like (note it). The run changes the towns for good: a throwaway save.

Run (towns grow with no transport: the base game gives them no growth without deliveries, so the dev mod simulates
it, Dev tools table "Simulate natural growth"):

1. Load the map, wait for `[SQOT_DEV] LOAD ok=true` and `MAIN visible=true`; build nothing. **Head start** (new map):
   `[SQOT] START` lines per town and a `START summary` (sizes before the head start), then
   `[SQOT] HEAD start towns=<n> rounds=2-5 edges=12`, then a `HEAD town= round= outcome=built` line every ~3-6 s; wait for
   `HEAD done` (~2-3 minutes for 16 towns) before pressing Quick (the head start keeps the main driver busy).
2. OT Dev window, **Simulate** tab: Seed 1, "Only towns near the camera" **unchecked** (all towns), Big towns better
   connected **checked**, Tour all towns when stopped **checked**; **Camera & tour** tab: Screenshots during the
   tour checked, s per view 3 (for the tour). Back in **Simulate**: press **Quick: 40 years** (green): as fast as
   possible (pace 0, since 2026-10-14; was 1 s per year), Fast fill every 4 years, a **build round** before each fill
   (the main driver held through the round and the fill), game speed 8x while running (all
   set by the button; the previous speed and the main mod's check pace come back at Stop). Check the `SIMGROW start`
   line (`mode=quick`, `towns=` the map's towns, `none=` about a quarter, `pace=0 fastFill=true fillEvery=4
   buildRound=true roundBuilds=6 roundMaxS=20 inflight=24 reachM=700 mainPace=check0.25s_cooldownx0.10 speed=4->8`,
   `mainPaused=false`). For a closer-to-natural run instead: Real s per year 2-5, Fill every 1 or 2 (each fill year
   costs the round + the fill, ~10-20 s); Fill every 8 is about twice as fast as 4 but coarser. "Build round" off falls
   back to the old wait for the main mod's own checks ("Wait for the main mod").
3. Leave it **~1.5-2 real minutes** for the 40 years (16 towns; was 4-6 before 2026-10-14; more towns take longer: the fill and the round scale with
   the growing towns; the clock stops while the game is paused). The Simulation line at the top shows simulated
   years, the last year's real seconds, buildings, `capacity built/target(%)`, and "build round (the main mod's turn,
   n s)" / "filling n towns" in a fill year. Each round a `SIMGROW round` line: `towns=` (grown since the last round)
   `checks= builds= edges= served=` (towns whose last check built nothing) `capped=` (hit 6 builds) `demandLeft=`
   (edges, sum of the last checks) `s= peak=` (jobs at once) `why=done|time|mainBusy|noMain` and `per=` (per town
   `Name:builds/checks:lastWhy:demandLeft`). The round's jobs are the main mod's own, logged `[SQOT] CHECK / PLAN /
   BUILT` as usual. Each year a `SIMGROW year` line with `s=`, `cap=`, `round=builds/towns roundS= filled= fillS=`.
   If 40 years take much longer than 6 minutes, send the `SIMGROW round` / `year` lines (round s vs fillS).
   `SIMGROW reactivate` / `resume`: a town the main mod's dose fill switched off is switched back on by the sim.
4. The year limit stops it (or press **Stop simulation**, red, Simulate tab or top of the window): `SIMGROW final`
   per town, `SIMGROW stop` (`s=`, `sPerYear=`, `speed=8->4`, `mainPace=restored`), then the Tour all towns flies to
   the 40 biggest towns with screenshots (`ALLTOWN`, `SHOT key=ALL_<id>`). Save at the end.

First natural-pace run (session `2026-10-12_2306_sqot-dev`, 30 s per year, 32 simulated years): the mod built
**nothing**, 388 CHECK lines all `why=open` (the game kept open frontage >= 2x the need and added 682 edges of its
own; docs/findings/towns.md "At the game's natural pace ..."). Since then the trigger is the growth demand (PLAN.md
6.3 "Growth-demand trigger"); the rerun checks it first.

Second run (session `2026-10-13_0018_top-up-598153`, Quick 40 years, 194 s): 50 BUILT, mod share 28 % overall but
8-10 % in the fast towns, 7 of 16 towns shore, 6 Nordic, no metropolis, shot 1 dropped (HISTORY.md 2026-10-13). Since
then: the fill year gives the main mod its turn before the forced houses, fast growers get bigger allowances, fewer
shore / Nordic towns, satellites, head start, tour primer (PLAN.md 6.3 "Real map round 2").

Third run (session `2026-10-13_0137_sqot-dev`, Quick 40 years, every town grows, 358 s): buildings 2134 -> 12067, but
the main driver checked each town ~3 times (75 CHECK, 59 BUILT: 28 head start + 31 demand); 10 of 16 towns got no
demand build, mod share 16 % (21-53 % where it built); 3 towns stayed development-off after the dose fill to the end
(FILL reactivate once each, later fills `active=false->false`). Since then: the build round (PLAN.md "Simulate natural
growth", build round) and the sim switching such towns back on.

The same run, the main mod's look: forms wide / lens 7 of 16, most towns round blobs, none gridded; Axbridge's head start
laid ~800 m of empty street to the map edge (HISTORY.md 2026-10-13). Since then (main mod): head start per form with a 280 m lead limit, map edge margin, character
towns, river bridges, organic <-> gridded era trend + "Town layout" setting (leave it at Organic), FILL reactivate after
every fill (PLAN.md 6.3 "Real map round 3"). A start year ~1900 shows the era trend; a map with a river through a town
or two (and its far bank free) gives the bridge a chance.

Fourth run (session `2026-10-13_0232_sqot-dev`, Testing grow On by mistake, every town grows, 357 s): 2468 -> 22228
buildings, mod share 41 % (target met), 2 character towns, 4 satellites (2 more dropped: link disconnected), 0 BRIDGE
lines; big linear / fingers / radiating towns blurred into blobs, Grays' south long empty loops (HISTORY.md 2026-10-13).
Since then (main mod): green wedges + wedge frames, own empty budget and a tighter lead, bridges toward narrow water near
a town, satellite links clear of streets, the grid look kept after the head start (PLAN.md 6.3 "Real map round 4").
Fifth run (session `2026-10-13_0342_sqot`, Testing grow Off, Quick, 16 towns, 264 s): 1992 -> 15517 buildings, 208
build-round builds, mod share 34 % (12-69 %; Bodmin 12 %); FRAME 15 plans, 12 built (Aylsham refused twice with the same
plan: a re-send bug), wedges only on the 5 armed towns; satellites 2 built, 3 seeds refused (`Collision` with entities
outside the snapshot), the rest `rare` / `noSite`; character towns Barrow (sprawling) and Bodmin (linear) read as blobs,
both 920 m from the map edge; Middlewich's long street up the hillside liked; house clusters next to industries 1-2 km
out (the generator's industry streets). Since then (round 5, PLAN.md 6.3 "Real map round 5"): "Streets at industries"
(default Off), satellites more common with an obstacle-aware site search, the frame re-send fixed, towns follow the
landscape (fewer round forms, more shore / hillside / valley / road towns, lobes along roads), character towns away from
the map edge, sprawling towns' outer streets get the dose fill; `spread=` / `hillRoad=` on SHAPE, `spread=` on ALLTOWN.
Note: the dev sim's years are simulated; the game calendar barely moves (the run stayed ~1900), so the era trend (item
21) only shows on a map started late (e.g. 1950) or in normal play.

What to check:

- **Neighbours differ (2026-10-13, ot_diverse):** in the tour shots, towns within a few km of each other mostly differ
  in form (clustered next to long / sprawling / radiating), while valley, coast and river towns still follow their site.
  STYLE lines (Debug log On): `nbr=<count>/...` > 0 for most towns after the first, `divPen=` with `form:` / `shape:`
  factors; send the STYLE lines and say which neighbouring pairs still look alike.
- **Build round (2026-10-13):** a `SIMGROW round` line every 4 years with `towns=` = the growing towns, `builds=` > 0,
  most towns `served` (their last check said ahead / open) and few `capped`; `s=` <= ~20-25; the Quick run <= ~2 min
  (`SIMGROW stop s=`; ~6 min before 2026-10-14). Every growing town has `[SQOT] BUILT trigger=demand` lines (`per=` builds > 0 in most rounds);
  mod share >= 40 % in every growing town. No `CNP` from two neighbour towns building at once (jobs in towns whose plan
  extents may meet, centres closer than rA + rB + 1.4 km, never run side by side, nor beside a neighbour's fill). No `SIMGROW stall ... why=off` without a later `SIMGROW resume`.

0. **The trigger (growth demand):**
   - `grep -c '\[SQOT\] BUILT.*ok=true' stdout.txt`: builds at all (first run 0). Expect builds in every growing town
     while it grows (one every 1-3 checks of that town), none in towns without growth (`SIMGROW final rate=0.00`).
   - `why=` mix: `grep -o 'SQOT\] CHECK.* why=[a-z]*' stdout.txt | grep -o 'why=[a-z]*' | sort | uniq -c`. Expect
     `demand` (build) and `ahead` (demand waiting for houses on our streets) in growing towns, `open` in static ones,
     `low` rare, `over` none. Only `open` again: the demand never reached `DEMAND_MIN_EDGES` (look at `demand=`).
   - CHECK `demand=` (edges of unserved target growth) rises between builds and drops after one; `perEdge=` (persons per
     street edge, ~13 at the start, rising); `ownOpen=` / `ownEdges=` (open lots / edges on our own streets: locked +
     this session's builds) stay at or under `lead=` (the game's open frontage x2, at most half the built lots). If
     `ownOpen` sits far above `lead` for many checks, the houses don't come to our streets (send the CHECK lines).
   - BUILT `trigger=demand`; PLAN `maxEdges=` sized to the demand in the organic styles (6-18), 28 / 30 / 36 in the grid
     / superblock / metropolis styles.
   - **Mod share of new streets** per town: BUILT `edges=` summed per town vs the town's CHECK `edges=` growth (first
     to last). **Targets (round 2): >= 40 % overall and >= 40 % in the fast towns** (`SIMGROW final` factor >= 5;
     2026-10-13: 28 % overall, fast 8-10 %). Fast towns: CHECK `fast=` above 1 (up to 3), `raw=` (backlog), PLAN
     `maxEdges=` up to 36, a re-check ~30 s after a build that left demand (the next CHECK of that town comes soon).
     In the Tour shots: are the growing towns' new quarters in the mod's style, or mostly the game's?
   - No empty ladders: our new streets get houses within a few checks (`ownOpen` falls between builds).
   - Fast fill years (`updateAllBuildings` true) jump the targets: expect a burst of `why=demand` right after a fill
     (capped at 2 increments of demand per town, `DEMAND_BANK`).

1. **Site-picked styles and forms:** `grep '\[SQOT\] STYLE\|SQOT_DEV\] STYLE' stdout.txt` (debug lines are
   `[SQOT] STYLE`): `styleSource=site styleWhy=<kind>:open=...` and `form= formWhy=`. Expect a mix per map: coast /
   valley / hill towns EU organic / MED hill / Nordic-like and `form=linear` or `clustered` with `formWhy=shape:linear`
   (valley, coast strip) or `draw:`; open plains EU extension / suburb / superblock (after 1950) with `sprawling` or
   `radiating`. Count forms: not all one kind.
2. **Valley / ridge / coast towns:** `[SQOT] SHAPE` lines with `shape=linear` / `ridge` / `fan` and their `reach=strong`,
   `armGap=` (gaps <= ~500 m), `streets=elong/...` growing over time; screenshots of 3-4 such towns from above: do they
   wind along the valley / coast, or round out?
3. **Locking in mountains:** BUILT `locked=` > 0 on shaped towns; in the screenshots, do vanilla side streets climb
   the slopes off our arm streets (they shouldn't), and do the locked streets get houses?
4. **Neighbouring towns:** towns 1.5-4 km apart: `shapeWhy=` "toward the neighbour" should be rare (`reach=mild`);
   twins (`neighbour town ... growing together`) only under 1.8 km; no town grows into its neighbour.
5. **Normal-size towns:** the trigger (`CHECK ... needsRoom=true why=demand`) fires every few checks while the town
   grows, `why=ahead` in between;
   increments small (`PLAN edges=` mostly 6-18); towns don't run ahead of demand (`armGap`, `open=` frontage).
6. **Metropolis auto pick:** `grep 'SQOT\] METRO' stdout.txt`: big flat towns (>= 4000 persons) get `on=true variant=`
   once in a while (a seeded ~35 %), the others `on=false why=small|site|rare`; a metropolis's PLAN lines
   `maxEdges=36`, BUILT `locked=` = edges, `FILL restore`. On a European map expect oldcore / radial / grid.
7. **Frame time:** `make perf` if SQPERF is on (else watch the game's frame time): no hitches when a big town plans
   (PLAN `us=` and `slices=`; > 50 ms in one slice is a problem).
8. **Errors / crashes:** `grep 'SQOT\] ERROR\|WARN' stdout.txt`, and any crash log (the SEND line before it).
9. **The tour** (started by the stop, or press **Tour all towns**): `ALLTOWN` lines list the 40 biggest towns with
   `orient= dens= style= form= shape= metro=` and the tour shoots each; `uv run tools/ot_shots.py` pairs the files
   (SHOT lines carry key `ALL_<town id>`).
10. **The simulated growth itself:** `grep 'SIMGROW' stdout.txt`: buildings rise each `SIMGROW year` (`+k`), the
   fast towns lead `top=`; `SIMGROW final`: unconnected towns (`rate=0.00`) stay at their start size, slow ones under
   ~2x, a few over 5x; `cap=` back near 100 % after each fill year (between fills it drops: the developer's pace);
   no `SIMGROW town ... ok=false` / `timeout`; `main=` mostly all towns checked, `timeout=false` (a timeout: the main
   mod's checks or builds took over 15 s); frame time stays smooth while the steps and fills are sent.

11. **Shore towns** (2026-10-12; PLAN.md 6.3 "Shore towns"):
   - Water detection: `grep 'SQOT\] TERRAIN' stdout.txt` `waterKind=kind:body:distance island= shore=length/stops`
     (body sea / lake / pond / river; `stops=` why the trace ended each way: len / far / steep / lost / closed / met).
     Lakes must read `lake` (or `sea` when larger than the 6 km trace), never `river`; ponds `pond`; river towns
     `river`. Many `lost` stops on plain coasts: the trace loses the boundary (send those TERRAIN lines).
   - Who becomes one: STYLE `form=shore formWhy=shore:p=0.55,sea[,island]` (or `formWhy=shape:shore`), `shapeGeom=shore
     ... shoreLen= depth= [closed] [island]`. Expect roughly half of the towns within ~450 m of a sea / lake shore,
     more on islands; none at rivers or ponds. Other coast towns: `SHAPE shoreFront=promenade`.
   - How they grow: SHAPE `shore=streets/houses cov=m depth=m`: streets share near the water >= ~0.8, `cov=` (shoreline
     covered) rising each build while `depth=` stays ~100-350 m; `armGap=` small (no empty strip along the shore far
     ahead of the houses); PLAN/BUILT normal (no `water` refusals in a row).
   - In the shots / from above: a waterfront street ~35-40 m from the water following the shore's curve (medium width
     on gentle shores, small where it bends), a row of small blocks behind it, the town long along the water and only
     a few blocks deep, wrapping around bays / along a lake shore / around the island; it stops at cliffs and headlands.
     Compare with a clustered coast town (round, reaching inland). A coastal metropolis (`METRO variant=corridor`):
     `shapeWhy=metropolis corridor shore`, the band along the shore.
   - Frame time: TERRAIN `us=` of coast towns (the trace: ~1500 samples once per town and session) and PLAN `us=`.

12. **Away from industries** (2026-10-12; PLAN.md 6.3 "Away from industries"): the map needs towns with industries
   within ~1.5 km (a generated map has them; a steel mill / coal mine / refinery 300-600 m from a town is the best case,
   a farm or food factory beside another town the light case).
   - The industry read: `grep 'SQOT\] IND' stdout.txt`: `IND industries=<count> ok=true us=` once per 5 minutes (the
     map's industry count; `ok=false` or 0 on a map with industries: the listing failed, send the line). `IND unknown
     file=...`: an industry file name the classifier doesn't know (treated as medium); send those names.
   - Per town: CHECK / STYLE / SHAPE `ind=count/nearest m/heavy count` (`ind=0`: none within 1.5 km). PLAN `indPen=`:
     share of the increment's new street length inside an industry buffer (heavy 500 m, medium 400 m, light 320 m around
     the works); `-` without industries. Expect `indPen=` mostly low (0.00-0.2) in towns with a heavy works nearby
     while the town has room elsewhere, higher only in towns boxed in (industry on several sides) or before ~1920
     (the preference is weaker then). SHAPE `indTurned=true`: a seeded shape axis was turned away from the works.
   - Screenshots: 2-3 towns next to a factory (from above, the factory in the frame), early and after ~20-30 years:
     the new quarters should lie on the side away from the works, with a gap of fields toward heavy industry; a town
     next to a farm grows almost as without it. A town hemmed in by works must still grow (BUILT lines keep coming).
   - Existing towns (Act on All towns on an older save) get the preference from the next load on; their saved frames
     keep their axis.

13. **Satellite villages** (2026-10-13; PLAN.md 6.3 "Real map round 2"): `grep 'SQOT\] SATELLITE' stdout.txt`.
   Expect 1-3 on a 16-town map (a seeded 30 % of the towns that reach ~300 buildings and get a demand build): `kind=seed
   site= dist=800-1500 link= road= ok=true`, `SATELLITE built kind=seed edges=` (link ~6-15 edges + core ~5), later
   `kind=grow` every few builds of that town while CHECK `sat=near/coreEdges@dist` shows houses near it (near >= 1.5 x
   core edges). `seed=none why=noSite|noDeadEnd|otherTown` lines: no site found (fine now and then). From above: a small
   separate cluster about a kilometre out, one street to the town, fields / meadow between (does the town put houses
   along the link's first stretch? note it), the cluster compact (within ~220 m), no streets in water or on steep land.
14. **Head start** (step 1): `HEAD start`, one `HEAD ... outcome=built` per town and round (`skip` / `empty` for a few
   is fine), `HEAD done jobs= built= edges=`; BUILT `trigger=head`, no FILL lines after them; the towns show their style
   at the start (Tour all towns before Quick if you like). Frame time smooth during it. A reload of that save later:
   no HEAD lines.
15. **Simulation order:** `SIMGROW year` lines of fill years: `sizesS=` (size callbacks), then `waitS= main=x/6
   mainBuilds=` (the main mod's turn **before** the fill), `filled= fillS=`, `waitFillS= mainFill=`. Expect `main=`
   mostly 4-6 of 6, `timeout=` sometimes; no `s=0.0` year right after a fill year (the clock stood still). Quick
   should take ~3-4 minutes. (This wait is the fallback with the build round off; at pace 0 quiet years show `s=0.1-0.5`.) `res=sent:..,same:..,busy:..,off:..` per year; **`SIMGROW stall`** lines: send them (a town
   that stopped getting growth: why=off means its development was switched off; `FILL reactivate` from the main mod
   means our fill did it; why=busy means a size command never answered).
16. **Tour:** `TOUR start ... primer=true` and `SHOT primer=true sessionShot=1`, then `SHOT n=1 ... sessionShot=2`;
   `uv run tools/ot_shots.py` should pair shot 1 with a file (the primer's file shows as "unmatched file").
17. **Styles (round 2):** STYLE lines: on an English / EU map Nordic rare (0-2 of 16; was 6), EU organic most, MED hill
   on steep sites, EU extension on gentler ones; `form=shore` on about a fifth of the sea / lake towns (was 7 of 16
   towns), more on islands. A flat river or valley town of >= 4000 persons may log `METRO ... on=true
   variant=corridor why=river:floor=...` (was `why=site`). SHAPE `ownShore=` vs `shore=`: if `ownShore ... depth=`
   stays <= ~350 m while `shore ... depth=` is 400-650 m, the deep streets are the game's / the starting core's.

18. **Distinct towns from the start** (round 3): `HEAD start ... rounds=2-5 leadM=280`, per job `HEAD ... round= of= form=
   character= shape= leadHeld= edge=`, `HEAD done ... forms=`. Target: the HEAD rounds show several forms (not 7 of 16
   wide: `form=wide` now only from a lens shape or a seeded draw), long / finger / radiating towns' head-start streets along
   their arms (Tour all towns **before** Quick: the towns should already differ in outline), no head-start street more
   than ~300 m beyond the houses (PLAN `leadHeld=` > 0 means the limit worked), no empty spurs.
19. **Character towns:** `grep 'SQOT\] CHARACTER\|character=yes' stdout.txt`. Target: 2-3 of 16 towns (`count=`), the
   most secluded (far from the others / near the edge: `picks=name:score:nnd:edge`), STYLE `form=` sprawling / linear /
   fingers / shore with `formWhy=character:secluded:...` (or `:island:`). In the shots: a sprawling character town in
   loose clusters with fields between (like Acton's gaps), or a long narrow town.
20. **Map edge:** `MAP bounds=` once at start (four numbers; `-` means the read failed: send it). No street within ~400 m
   of the edge (PLAN `edgeHeld=` > 0 near the edge; STYLE `edgeDist=`), STYLE `shapeWhy=... (turned away from the map
   edge)` for edge towns; no arm aimed at the edge in the shots.
21. **Grid share by era:** STYLE `gridBias=e=..,set=2,look=..` and `style=`: before ~1900 mostly EU organic (grid-ish
   EU extension / ensanche / NA grid ~20-25 %), 1930 ~30 %, after 1950 ~half (suburbs, superblocks). In the shots of
   later years: some planned grid towns and straighter outer districts (extension rings) around organic cores. The STYLE
   line comes again each simulated decade (the outer zone follows the years): `gridLook=` / `outer=` change.
22. **River bridges:** `grep 'SQOT\] BRIDGE' stdout.txt`: `outcome=none why=...` for river towns without a crossing,
   `outcome=plan span= ... type=::/infrastructure/bridge/stone.bridge typeIndex=`, then SEND / BUILT or `outcome=refused
   why=precheck msgs=...` (send those lines: the first script bridge in this repo). If built: `outcome=built bridgeEdges=1`,
   a stone bridge in the shot, houses on the far street and later the mod's streets growing from the T on the far bank.
   A crash right after a `BRIDGE outcome=plan` / SEND line: send the crash log.
23. **FILL active:** `grep 'FILL.*active=\|FILL reactivate' stdout.txt`: FILL lines `active=true->develop:x->restore:y`
   tell which command turns development off (send them); `FILL reactivate ... after=` after every such fill; no long
   `SIMGROW stall ... why=off`.

24. **Form at large size (round 4, ot_wedge):** linear / ridge / cross / fingers towns (STYLE `shape=`; radiating forms
   use cross) past ~1000 buildings: in the tour shots the arms still read (linear clearly long, fingers / cross with
   open green wedges between the arms), the game's own streets mostly inside the core frame and along the arms. Logs:
   `grep 'SQOT\] FRAME' stdout.txt`: `outcome=plan ... links= edges= coreR=` then `outcome=built frames=` in every armed
   growing town (a few per town over the run; `outcome=refused` rare: send those lines); BUILT after a frame build
   `locked=` = `edges=`; PLAN `wedgeHeld=n@coreR` on armed towns (n > 0 means the reserve held pieces back). SHAPE
   `houses=elong/arms/...`: linear houses elong >= 1.8 at 1000+ buildings, fingers arms >= 3. Look whether game streets
   cross or attach to the frame (they shouldn't), whether the frame's outer side gets houses, and where the game's growth
   leaks out (beside the arm gates?).
25. **No empty loops (round 4):** PLAN `ownEmpty=m/cap` stays <= ~1500 m + 8 % of the town's street length (CHECK
   `why=ahead` / PLAN `edges=0` with `ownEmpty:` when it is reached); `emptyLen=` (all unhoused streets, the game's too)
   well below the fourth run's 4-17 km; in the shots no streets / loops more than ~400 m beyond the houses (grid / ensanche
   frames only next to housed blocks). The mod share should still be >= 40 % overall (fourth run 41 %).
26. **Bridges tried (round 4):** a `BRIDGE` line for every town past 150 buildings at its first demand build: `outcome=none
   why=noRiver river=false narrow=0` where no narrow water lies within 1.5 km, `why=rare` (a seeded 25 %), else `outcome=plan`
   (or `none why=far|noSite|noCrossing|otherTown cands= deadEnds=`). A town by a river or narrow lake arm should show
   `narrow=` > 0. If built: the bridge in the shots (a bridge edge, the far T street, houses later).
27. **Satellites connected (round 4):** `SATELLITE ... kind=seed ... dropped=-` (no `disconnected` / `crossesExisting` /
   `nearExisting` on the link), `SATELLITE built`; from above the link reaches the cluster without crossing a street.

28. **No house clusters at industries (round 5):** the INDSTREETS line at every start (`choice=off ... true->false
   applied=true`). Before Quick, fly over 3-4 industries 1-2 km from towns (farms, mines, a steel mill): no small street
   grid beside them; after the run, no house clusters there. Industries still work: their windows show production
   (cargo to a station you build next to one, if you like). Compare with an earlier run's map (Barnes, Ilkeston). If
   the industries get no streets at all and something looks broken (an industry without its entrance road, a
   warning), send a shot: Game default brings the streets back.
29. **Satellites built (round 5):** `grep 'SQOT_DEV\] SATELLITE\|SQOT\] SATELLITE' stdout.txt`. Target: **1-3 built** on
   a 16-town map (`SATELLITE built kind=seed`); `kind=seed ... why=seeded|quota obst=<segs>/<boxes> tries=`;
   `refused=precheck` rare, and then with `partners=ent<id>:<kind>` (field / track / street / con: send those lines) and
   a next try ~90 s later at another site (`tries=` up to 4). `on=false why=rare` for a bit under half of the towns >=
   250 buildings. From above: never next to a heavy works (a farm or food factory nearby is fine), meadow between.
30. **Frames built (round 5):** every `FRAME outcome=plan` followed by `outcome=built` (or `outcome=pruned kept= dropped=`
   then `built`); `outcome=refused` only when every link failed. No two identical REFUSED lines in a row for a frame.
31. **Towns follow the landscape (round 5):** STYLE `form=`: clustered + wide at most ~4 of 16 towns (fifth run 7);
   more linear / fingers / sprawling / shore. Shore towns: `form=shore` on ~35-45 % of the sea / lake towns (islands
   ~60 %), long strips along the water a few blocks deep (SHAPE `shore=... depth=` <= ~280 m). SHAPE `spread=ratio/beyond
   %/lobes` and ALLTOWN `spread=`: a round town reads ~1.0-1.3, a strip / finger / lobed town 1.5+ with beyond >= 10 %;
   send the ALLTOWN lines. In the shots: fewer round blobs, towns along coasts, valley floors, hillsides and roads.
32. **Hill road (round 5, the user on Middlewich):** hillside / valley towns (STYLE `shapeWhy=hillside: along the contour`
   or `valley:`): SHAPE `hillRoad=len/climb/houses` with len 500+ m, climb 20+ m and houses along it; from above one long
   gently curving street up the slope lined with houses, small terraces off it, steep ground left green.
33. **Character towns read (round 5):** CHARACTER `picks=name:score:nnd:edge` with edge >= 1300 m; a sprawling character
   town with lobes (SHAPE `spread=` lobes >= 2 or ratio >= 1.4; FILL lines `kind=dose` after its builds, `why=lobes`), a
   linear one with long arms (houses elong >= 1.8 at 700+ buildings); PLAN `ownEmpty=` below its cap most of the time.

### Motif checks (phase M0 framework, 2026-10-13; M1 terrain / water motifs 38-42; M2 road / village motifs 43-47; M3 town structure / era motifs 48-52; M4 more terrain 53-58)
`grep 'SQOT\] MOTIF\|SQOT_DEV\] MOTIF' stdout.txt`; PLAN.md 6.3 "Motifs: the framework".
34. **Framework (M0):** every STYLE line carries `motifs=` (`-`, or `id:score:source`). M0 registers no drawn kind, so
    the towns look as in round 5: `MOTIF ... event=pick kind=crescent src=derived why=style:crescents=n` on organic /
    suburb / metropolis towns with crescent meadows, `kind=hill_road src=derived why=shape:hillside_contour` on hillside
    towns drawn linear along the contour; `event=build ... edges=<build>/<town> houses=` after their builds (crescent:
    arc streets and houses just outside the meadow; hill road: the climbing arm's streets, `info=` = SHAPE `hillRoad=`).
    At most 2 motifs per town. No `WARN stage=motif`. ALLTOWN `motifs=` in the dev tour lines.
35. **Old saves:** a save from before M0 loads, its towns keep their look (no drawn motifs: frames without `mo`).
36. **Dev forced motif:** Town tab, pick a town, "Motif for Grow now / Plan only (dev)" = Hill road, Plan only: STYLE
    `motifs=hill_road:1.00:forced` and `shape=linear`, `MOTIF ... src=forced why=forced(dev)`, QUEUE `motif=hill_road`.
    Crescent on a grid town: one crescent meadow (STYLE `motifs=crescent:...:forced`, PLAN `crescents=1/1` once the plan
    reaches it). Back to Main mod (auto) afterwards.
37. **Green relax:** PLAN `greenRelax=n` appears only where a town's dead ends all sat inside green reserves (rare); that
    town then grows on instead of logging `planEmpty` over and over.
38. **M1 picks:** `MOTIF ... event=pick kind=hill_climb|valley_fishbone|harbour_crescent|fishing_village src=drawn why=`
    on towns whose site fits (`why=slope:grade=..,range=..` / `valley:contrast=..` / `bay:ratio=..,chord=..` /
    `slopingShore:grade=..,water=..`); none on flat inland towns; never both hill_climb and valley_fishbone, nor both
    harbour and village, in one town; STYLE `motifs=` lists them. Expect roughly a third to half of the hilly / valley
    towns with a land motif, most bay towns with a harbour, a few small sloped coast towns with a village.
39. **Hill climb (the user's Middlewich favourite, deliberate):** MOTIF build lines `kind=hill_climb ... info=len=<built>/
    <planned>,climb=,grade=,terraces=<built>/<planned>,stop=,anchors=<n>/<links>`: len grows over the builds to 400+ m,
    grade <= ~0.07, climb 20+ m, terraces 1-3. From above: one street leaving the town up the slope, gently bending
    along the contour where it is steep (no hairpins), houses along it, 1-3 small loops on flatter shelves beside it,
    open green between them (no mod streets in a ~70-100 m corridor; the game's own streets may still appear: note it).
    `anchors=0/0` for long means the climb never found a dead end to start from: send that town's lines + a shot.
40. **Valley fishbone:** `info=spine=,ribs=<built>/<planned>,sides=l+r,spacing=`: ribs on both sides, spacing ~80-140 m.
    From above: a main street along the valley floor with short dead-end lanes up both slopes like a fishbone, the lanes
    stopping where the slope gets steep.
41. **Harbour crescent:** `info=front=,cover=<built>/<planned>,lanes=,bay=`: cover rising toward 0.7+; FILL lines
    `why=motif` after builds with crescent streets. From above: a curved street around the bay ~35-40 m from the water,
    short streets inland off it, a dense row of houses facing the water; no promenade (ot_shore) elsewhere in that town.
42. **Fishing village (small sloped coast towns):** `info=front=,streets=<built>/<planned>,len=,heading=`: 3-4 streets.
    From above: beside the core, a waterfront street and 3-4 narrow parallel streets straight up the slope, dense.
    For every M1 motif: no `WARN stage=motif`, no REFUSED lines naming `mhc` / `mvf` / `mhb` / `mfv` keys over and over
    (send them), dev picker (Town tab) has the four new entries for forced screenshots.

43. **Country roads (M2):** one `ROADS town= roads= text=<n>:<out m>@<heading>/...;j=<junctions>;f=<edge reads>
    junctions=<own>/<all> segs= fetched= us=` per town and session (debug), `us` a few ms at most (`fetched` <= 250);
    STYLE `roads=` the same text. A town on a through road: 2 roads out of town, each followed 1-1.7 km (`out`); towns
    with no country road (rare): `roads=-`, and none of the three M2 motifs. No `WARN stage=roads`.
44. **M2 picks:** `MOTIF ... event=pick kind=ribbon_village|village_green|crossroads_hamlet src=drawn why=` with
    `road:n=,out=` / `fork:angle=,grade=` or `edge:grade=` / `crossroads:d=,deg=`; never both ribbon and green in one
    town; none in tier-4 towns (cities) and metropolises; ribbon / green fewer from 1950. Expect roughly one in five small
    or medium towns with a ribbon, one in ten with a green, one in five with a crossroads hamlet where a crossroads of
    country roads lies 0.45-1.6 km out (all three share the towns' two motif slots with the M1 kinds).
45. **Ribbon village (Strassendorf):** MOTIF build lines `kind=ribbon_village ... info=ribbon=<built>/<planned>,lanes=
    <built>/<planned>,off=<m>,roadSide=<houses>,stop=,anchors=<n>/<links>`: ribbon growing toward 300-700 m, `off` 32-45,
    `roadSide` (houses between the street and the road) rising; FILL `why=motif` after builds with ribbon streets
    (DevelopAt on the road side). From above: one street running beside a country road out of town ~35-45 m from it,
    a single row of houses between them facing the road side, houses on its far side too, 2-4 short dead-end lanes off
    the far side, meadow behind (no other mod streets in the strip). BUILT `locked=` counts its edges (no game side
    streets on it). `anchors=0/0` for long: the town has no dead end near where the road leaves; send its lines + a shot.
46. **Village green:** `info=shape=lens|triangle,ring=<built>/<planned>,cover=,onGreen=,ring=,d=,ours=,anchors=`: cover
    rising to 0.9+ (the ring closed), `onGreen` (houses deeper inside than a lot) staying low. From above: 240-400 m
    from the centre a lens-shaped green (the street splits around it and joins again, ~220-280 m long, ~130-170 m
    wide), or at a fork of two roads a triangle (sides 220-270 m) pointing at the town, linked by a short street;
    houses on both sides of its streets, a meadow in the middle; no mod street inside; the town's streets meet it only
    head on. The game's own streets may still enter the middle: note it. A green that moves between sessions (a
    second, half-built ring elsewhere): send the town's MOTIF lines.
47. **Crossroads hamlet:** `SATELLITE ... why=hamlet at=crossroads junction=<m from the junction>@<m from the centre>`
    (the satellite stage seeds it from 120 buildings, no seeded draw), then `SATELLITE built`; MOTIF `kind=crossroads_
    hamlet info=site=x:y,junction=,at=crossroads,near=<houses>,coreEdges=` (`none:waiting` before). Other satellites
    now show `at=crossroads|light|ring` and `light=<m to a farm / light works>`: expect some `at=light` beside farms,
    never a site beside heavy works. From above: a small cluster 90-170 m from a junction of country roads, in the
    quadrant facing the town, its own link street from the town running beside the road (never across it, never joined
    to it: country-road nodes are not joinable). A refused hamlet (REFUSED / SATELLITE `ok=false`): send `partners=`.
    For every M2 motif: no `WARN stage=motif|roads`, no REFUSED lines naming `mrb` / `mvg` keys over and over, no street
    of the mod across a country road beyond the town (ot_select now blocks plan pieces across the traced roads); dev
    picker (Town tab) has the three new entries (Crossroads hamlet + Grow now seeds the hamlet at once when a crossroads
    qualifies; otherwise MOTIF `none:noJunction`).

48. **M3 picks:** `MOTIF ... event=pick kind=ring_road|workers_terraces|culdesac_pods src=drawn why=` with
    `core:r=,era=,slope=` / `light:file=,d=` / `suburb:era=,slope=`: rings on EU organic / extension / MED hill towns of
    500+ people (none in grids, villages, metropolises), terraces only before ~1930 and only where a light factory
    (food, textiles, brewery ...; never a farm) stands 120-900 m beyond the houses with no heavy works beside it, pods only
    from ~1950. Expect a ring on maybe one in ten old EU towns, terraces at a few towns with factories in early starts,
    pods on a fifth of the later suburban towns.
49. **Ring road:** MOTIF build lines `kind=ring_road ... info=R=<m>(picked|session|saved|locked),arcs=,closedPlan=,
    planned=<m>/<circumference>,built=,cover=,radials=,joints=,stubs=,tees=,blocked=,awkward=,class=,outer=`: `cover`
    rising, `radials` (the ring's junctions with the town's streets) rising; `R=...(saved)` in a later session (same R).
    From above: a curved street around the old core just beyond its dead-end streets, the core's radial streets running
    straight on into it (head on), medium where gentle; outside it straighter, more regular extension blocks than in the
    core. Where the town's own streets already cross the circle, or at water: only arcs between two radial streets (no
    street cut mid-way, no ring across a street). A ring that moves between sessions (a second, half-built circle): send
    the town's MOTIF lines. `none:noJoint` / `none:blocked` for long: the core has no dead ends near the ring; send a shot.
50. **Station quarter (gameplay hook; read from files, unverified):** build a rail passenger station 200-800 m from a
    town's houses, then wait up to 2 minutes: `STATIONS stations=<n> dirs=<n with a direction> ok=true` (per listing;
    `ok=false err=...` or `stations=0` with stations on the map: send the lines), `STATIONS town=<id> n= nearest=<m>@<deg>
    front=<fx,fy|unknown> tracks=<n> file=<construction file>` for the town, then `MOTIF ... kind=station_quarter
    src=derived why=station:d=..,n=..` and after builds `info=station=<d>@<deg>,side=town|away|guess,grid=3x3|4x4,
    sides=<built>/<planned>,link=<m>/<m>,anchors=`. From above: a small square grid of streets on the station's front
    side (where the passengers come out), squared to the station, a station square street along its front and a straight
    street from the town to it; nothing across the tracks. Check `front=`: the grid must be on the entrance side; if it
    is behind the platforms (the -Y rule wrong for that layout, e.g. a terminus) note the station type and send a shot.
    `side=away`: the entrance faces away from the town (no link street across the tracks; the grid grows only where a
    dead end of the town's streets, e.g. the station's own access street if it is a plain town-street dead end, comes
    within reach of its junctions; else it stays unbuilt: note it). Demolish the station: within 2 minutes the quarter's unbuilt streets are
    no longer planned (MOTIF lines stop).
51. **Workers' terraces (early starts, factories near towns):** `info=works=<file>@<d>,rows=<built>/<planned>,spine=,
    sp=,half=,anchors=`: rows built rising; FILL `why=motif` after builds with rows. From above: a short street from the
    town toward the factory and 3-5 short parallel rows square to it near the works (~40-50 m apart), dense houses in
    rows; the town's other streets still keep away from the works. No terraces at farms or next to heavy works.
52. **Cul-de-sac pods (from 1950):** `info=collector=<m beyond the houses>/<planned>,closes=<built>/<planned>,heads=plain,
    dir=,class=,inGreen=,stop=,anchors=`: closes rising to 3-6, `inGreen` (other streets in the green behind the closes)
    staying low. From above: a gently curving street out of town with short dead-end closes on alternate sides, no turning
    heads (plain dead ends), meadow behind them; BUILT `locked=` counts the pods' edges. The game's own streets in the
    green: note them.
    For every M3 motif: no `WARN stage=motif`, no REFUSED lines naming `mrr` / `msq` / `mwt` / `mcp` keys over and over
    (send them), the dev picker (Town tab) has the four new entries (Station quarter: forced only shows where a station is
    near; otherwise MOTIF `none:noStation`).

53. **M4 picks:** `MOTIF ... event=pick kind=switchbacks|ridge_street|headland_street src=drawn why=` with
    `steep:grade=,range=,max=` / `ridge:contrast=,level=` / `cliff:h=<m above the water>,d=<m to the brink>`: switchbacks
    only on slopes of ~6.5 %+ (relief) that still have ground within maxSlope for a bend (shared with the hill climb:
    one land motif per town, never on a crest), ridge streets only on crest towns, headland streets only where the coast
    is a cliff 8 m+ high within ~550 m (never on a beach; one shore motif per town with harbour / village). A town with
    a station or a bridge draws exactly the motifs it would draw without (the event quarters take no slot, M4 fix).
54. **Switchbacks:** MOTIF build lines `kind=switchbacks ... info=len=<built>/<planned>,bends=<built>/<planned>(want n),
    R=80,climb=,grade=,legs=,leg=,stop=,atBends=<houses near the bends>,anchors=`: bends built rising to 2-4, grade <= the
    style's maxSlope. From above: beside the town a street climbing the slope in long legs along it, joined by tight
    hairpin bends (80 m radius), houses clustered at the bends (FILL `why=motif` after builds with bend streets), green
    slope between the legs (no mod streets there). A bend refused over and over (REFUSED naming `msb` keys with `:H`):
    send the lines and a shot (the bend's terrain); `stop=bend:steep` with `bends=1/1`: the slope had no legal place for
    a second bend.
55. **Ridge street:** `info=spine=<built>/<planned>,crest=<share on the crest>,spurs=<built>/<planned>,sides=l+r,stop=,
    anchors=`: crest ~1.0, spurs only where a flank is gentle. From above: a street along the crest through the town,
    houses on both sides, a few short dead-end lanes down the gentler flank, the steep flanks green (no mod streets).
56. **Headland street:** `info=front=<built>/<planned>,setback=<min>..<mean>(plan <m>),seaward=<streets between it and
    the cliff>,lanes=,houses=<inland>/<sea side>,cliff=<h>m@<d>,stop=,anchors=`: setback ~40 m, `seaward=0`, houses mostly
    inland. From above: a street along the cliff top ~40 m inland of the edge, a row of houses on its inland side facing
    the sea (FILL `why=motif`), short dead-end lanes inland, nothing between the street and the cliff; no promenade
    below the cliff.
57. **Bridgehead quarter (river towns that built their bridge):** after `BRIDGE outcome=built`, `MOTIF ... event=pick
    kind=bridgehead_quarter src=derived why=bridge:session` (a later session: `why=bridge:frame`, the bridge found in the
    snapshot), then `info=bridge=plan|graph,grid=4x3|4x4,sides=<built>/<planned>,linked=<sides off the cross street's
    dead ends>,heading=`. From above: on the far bank a small square grid squared to the bridge, its first row the
    bridge's cross street continued straight on from both ends, nothing back across the river; BUILT `locked=` counts its
    edges. `none:noBridgeEdge` on a bridged town: the snapshot didn't show the bridge over water; send the lines.
58. **M4 fixes and the era range (1900+):** `MOTIF ... event=waitGiveUp piece=<close / row / spur> line=<its main line's
    next piece> plans=6` appears only where the main line's next piece is refused over and over (rare; send the town's
    REFUSED lines); afterwards that branch is never built. A 1900 start: towns organic (STYLE `gridBias` e=0 until 1910,
    no ensanche before 1920, no EU organic extension ring before 1915), rings and workers' terraces on the old towns
    (terraces to ~1935, fading by 1950); a 1970 start: more grid / suburb towns, pods, fewer rings.
    For every M4 motif: no `WARN stage=motif`, no REFUSED lines naming `msb` / `mrs` / `mhl` / `mbh` keys over and over
    (send them); the dev picker (Town tab) has the four new entries (Bridgehead quarter: forced only shows on a bridged
    town, otherwise MOTIF `none:noBridge`).

### Forest checks (phase F, 2026-10-13; PLAN.md 6.3 "Forest-aware towns"; the tree read is unverified)

Use a map with forests (temperate or subarctic, normal or more trees), a 1900-1930 start for hug towns and a 1980+ start
(or a later save) for clearing towns.

59. **The read works:** one `FOREST town= ... groups= reads= trees= stride= capped= cells= dense= share= p50= p90= listUs= us=
    slices= err=-` per town at its first check (again after ~20 min). Expect groups > 0 and trees in the thousands on a
    forested map; `err=-`. Send the lines. If `groups=0` everywhere or `err=noAssetGroupType` / `octree:...`, the read
    found nothing (towns plan as before): send them and a screenshot of a forest near a town. Cost: `listUs` (one octree
    call) and `us` / `slices` (3 ms slices): note any stutter at a town's first check on a big forested map.
60. **Density calibration:** `p50` / `p90` are trees per hectare in the 50 m cells with trees. Dense forest should give
    p90 well above 90 (the cover's full value) and open farmland few cells; `share=` should match what you see (0.3 = about
    a third of the land within 1 km is forest). If a visibly wooded town logs share ~0, or open land logs a high share,
    send the FOREST lines and a screenshot (the LIGHT_HA 25 / DENSE_HA 90 thresholds move).
61. **Hug vs clear:** STYLE `forest=<share>:hug|clear|none` on each town; in an early start most small organic towns with
    forest around them say `hug`, grids / big towns / later years `clear`, towns in open country `none`. PLAN lines of hug
    towns: `forestCut=` mostly 0.00-0.2 (the mod's new streets in forest), `forestHeld=` > 0 where the forest is near;
    clear towns' forestCut follows the land. ALLTOWN `forest=` the same per town.
62. **The look:** a hug town in a forest grows fingers along clearings and meadows and streets along the forest edge with
    houses on the open side; the forest stays (the game's own growth may still nibble at it: say how much). A boxed-in hug
    town keeps growing slowly (PLAN `forestRelax=` > 0, a few streets into the forest per build). A clear town builds
    straight through. Screenshots of one of each, from above.

Send back: `grep 'SQOT' stdout.txt` (or the whole log), the save's map settings, screenshots of the interesting towns
(or the Tour all towns shots), and what you see.

## Starting town size test (2026-10-13; PLAN.md 6.3 "Neighbour diversity, terrain first, Starting town size")

Question: does the "Starting town size" setting (baseConfig `populationDensity` x0.35 in preRunFn) give a new map smaller
starting town cores (fewer streets), or only fewer residents?

1. Mods: `square_organic_towns` (+ `square_organic_towns_dev` for the tour). Debug log On, Act on New towns only, other
   settings default. Note the map settings (size, seed, terrain, names, year; base "Population" at 100 %).
2. Map A: a NEW map, **Starting town size: Game size**. Right after load, before Quick or anything else: wait for the
   `[SQOT] START summary` line (it comes before `HEAD start`), then OT Dev **Tour all towns** (screenshots on), then quit
   to the menu.
3. Map B: a NEW map with the **same seed and settings**, **Starting town size: Small**. Same steps.
4. Send: both sessions' `[SQOT] TOWNSIZE` lines (`populationDensity=1->1` vs `1->0.35`, `applied=`), `INIT ... popDensity=`,
   every `START` line and the `START summary` lines, and the tour shots of a few towns side by side.
   - Cores shrink: B's `edges=` / `length=` / `buildings=` medians clearly lower than A's (and the shots show smaller
     cores). Then the head start's scaling (`HEAD start rounds=4-7 edges=18`) can be judged too.
   - Only residents: edges / length about the same, `cap=` / `actual=` lower (or nothing differs at all: the map preview
     generated the towns before preRunFn). Then the setting needs another lever (next round).
5. Optional control: map C, same seed, Game size but the base game's own **Population 50 %** (advanced settings): if C
   differs from A and B doesn't, the generator reads the menu's value, not baseConfig.

## Vanilla baseline (2026-10-13, session `2026-10-13_2355_sqot`)

Vanilla vs Organic Towns after 40 simulated years, with metrics, shot pairs and the rerun recipe:
[BASELINE_VANILLA.md](BASELINE_VANILLA.md). Rerun it after a big round and add a column there.
- 2026-10-14: same-seed comparison against true vanilla (0°, seed `U8Qxgisp4I`, session `2026-10-14_0119_sqot`): [BASELINE_VANILLA.md](BASELINE_VANILLA.md) "Same-seed comparison 2026-10-14", data and shots in `compare/2026-10-14_U8Qxgisp4I/` (site page `/square_organic_towns/comparisons/2026-10-14_U8Qxgisp4I/`).
