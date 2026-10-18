# Supply Gap Overview: in-game release checklist

Status: open. Written for rev 1 (2026-10-09); rev 4 is released, but no box here is ticked off yet. Keep as
the regression checklist. Since rev 4 starved buildings show a red question mark (`question_red`) where
this file says "exclamation".

What is still unverified after the Phase 2 spike (PLAN "Release cleanup"). The log is quiet now: one
`[SQSG] INIT` line, one `[SQSG] LOAD saved=... tries=N` line per load, `[SQSG] saved on=...` when the
checkbox changes, plus `[SQSG] ERR ...` lines on failures.

```sh
grep -h "\[SQSG\]\|square_supply_gaps" ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt
```

If the game crashes, also send `crash_dump/error.json` and the newest `crash_dump/*.json`.

**Setup:** mod linked (`make link`). A save with a few towns, one truck line delivering a cargo into a
town (e.g. fuel to industrial buildings), and a bus line. Save first.

1. **Default off, remembered per save** (PLAN "Per-save state").
   - [ ] New game: no markers, the ridge button reads **Gaps**. Log: `[SQSG] INIT mapEditor=false on=false ...`
     and `[SQSG] LOAD saved=off tries=0`.
   - [ ] Add the mod to an old save (enabled in the mod list, save never had it): loads with **no** add
     warning, no markers, `LOAD saved=off`.
   - [ ] Click **Gaps**, tick **Show supply gaps**: arrows appear within ~1 s, the button reads **Gaps: on**,
     log `[SQSG] saved on=true`. Ticking it again after an untick logs once per change, never per tick.
   - [ ] Save, quit to the main menu, load that save **without opening the window**: `LOAD saved=on`, arrows
     come back within ~2 s, no off/on flicker. Also loading it paused.
   - [ ] Untick, save, reload: `LOAD saved=off`, no markers.
   - [ ] No stutter at load or once a second while panning (on your largest save too).
2. **Window.** Click **Gaps** (overlay on).
   - [ ] Title "Supply Gap Overview"; "Show supply gaps" ticked; "In view: <towns on screen>" header; no debug text.
   - [ ] Cargo rows show an icon, the name and `unreached · empty / needed`; hover a row and each
     checkbox: short tooltips.
   - [ ] Legend: arrow line, and the exclamation line while "Include in-range but empty" is ticked.
   - [ ] Options: Only towns in view (on), Include in-range but empty (on), Area labels (on), Count stops
     without a line (off). Spacing looks even; text fits the window.
3. **Starved (exclamation).** Find a building in range of the delivering stop whose input stock reads 0
   (building window, e.g. "fuel 0/2").
   - [ ] ~20 to 30 s after load it shows an exclamation, and counts in that cargo's middle number.
   - [ ] Untick **Include in-range but empty**: the exclamations go, rows switch to `unreached / needed`.
   - [ ] A building that then gets a delivery loses its exclamation within ~10 s.
4. **Area labels.** Pick the delivered cargo.
   - [ ] Under the town name: one row per district with a coloured bar and a `[icon] NN%` pill (pan away
     and back if nothing shows). The % matches the markers there; one gap left never reads 100 %.
   - [ ] "All needed": up to 3 pills per district, worst first. Untick **Area labels**: rows go within ~1 s.
   - [ ] Cargo Flow layer: our pill row under each district label, none on its town labels.
5. **In view.** Several towns a few km apart.
   - [ ] Only towns on screen are counted and marked; a town whose name is off screen but whose
     buildings are visible still counts; no flicker when panning across a town edge.
   - [ ] Jump to a new town: its counts appear within 1 to 2 s, with no partial counts first.
   - [ ] Untick **Only towns in view**: "Whole map: N towns", counts grow to the whole map.
6. **While building.** Place a truck stop near marked buildings, not on a line: markers stay. Tick **Count
   stops without a line**: those markers go within ~1 s. Pause the game and place another stop: the
   markers still update.
7. **Save safety.**
   - [ ] Untick **Show supply gaps**: every marker and label row disappears at once.
   - [ ] Quit to the main menu, disable the mod, load a save that has the flag stored (step 1): only the
     game's removed-mod **warning** (severityRemove Warning), then it loads; no errors, no markers. (Quit to
     the menu before any `make unlink`.)
   - [ ] The map editor shows no Gaps button and no markers.
8. **Errors.** Paste any `[SQSG] ERR ...` lines.
9. **Perf (DEBUG run, optional but wanted once).** Quit to the main menu, set `local DEBUG <const> = true`
   in `mods/square_supply_gaps/content/supply_gaps/sg_overlay.tl`, load your **largest** save (saved with the overlay on) without
   opening the window. Leave the camera still for ~1 min, then pan across a few towns for ~1 min, then open
   the window and untick **Only towns in view** for ~1 min. Then:
   ```sh
   grep -h "\[SQSG\] PERF" ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt
   ```
   - [ ] Paste the PERF lines (one every 30 ticks). `clock=wall` (engine wall clock, not os.clock).
   - [ ] Camera still: `avgMs` and `maxMs` low (target: avg ~1-3 ms, max under ~8 ms); `skips=` most of
     the 30 ticks; `plans=` / `labelBuilds=` near 0.
   - [ ] First lines after load: `boxPass=running` then `done`; no tick far above the others (the box pass
     and building reads are budgeted, `BOX_BUDGET_MS` 3 / `READ_BUDGET_MS` 6).
   - [ ] `split(avg/max)=` shows which stage dominates (lines, catch, map, boxes, scope, read, model,
     markers, labels); note the biggest one.
   - [ ] No visible hitch once a second while panning. Set `DEBUG` back to `false` afterwards.

Copy the verified facts (mission markers in free play, arrow/exclamation types, catchables are the
building entity, starved rule, district labels via the TownHudIcon wrap) to `docs/findings.md`.
