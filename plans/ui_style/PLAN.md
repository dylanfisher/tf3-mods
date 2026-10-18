# Native UI style for our mods (top-bar buttons, windows)

The rules themselves live in `docs/ui-guide.md`; this file keeps the research and open work.

Status: top-bar buttons done 2026-10-12 (unreleased, not yet checked in game); window kit proposed, not started.

Reference: **Timetables** (`celmi_timetables`, `.cache/subscribed/celmi_timetables/`) is featured by Urban
Games and went through their review. It looks native because it reuses base widgets, base classes and base
nine-patch textures. Paths below: `P = .cache/subscribed/celmi_timetables/content/timetable/plugins/`,
`B = .cache/game/base/content/gui/`.

## Top-bar ("ridge") buttons: done

Every mod with a `::MainModButtonAreaExtension` button (Better Minimap, Industry Flows, Supply Gaps, Problem
Radar, Stress Test) has the mod.json param `hudButtonStyle` = { "Text", "Icon" }, default Icon (runtime value
1 = Text; anything else, including a missing param, = Icon).

- Icon style = a base `builtin.ToggleButton`, like the data layers button (`B/layers/layers_button_ridge.tl:529-539`)
  and Timetables' ridge button (`P/timetables_plugin.script.tl:469-565`). UG's review of Timetables asked for
  this: a plain Button paints no background.
- The base rules give everything: `BaseMedium` tile unchecked, `AccentMedium` checked, hover contour, sounds,
  `NeutralLightest` icon (`B/main/builtin.css.lua:138-240`). We set **no colour** inline (it would override
  the states). State colour goes on the button's contour instead (`borderColor` inline; the base border
  image is invisible except on hover): Supply Gaps green (`Ok`) while the overlay is on, Photo Mode green while its highest graphics are on (window
  closed or open), Problem Radar none (its
  dot shows the worst tier). Unverified in game: that the inline contour shows in
  every state (it replaces the hover contour while set).
- Size: 8 px padding (the base default) around a 24 px icon = a 40 px tile, as big as the layers button and
  Timetables' button in game (2026-10-12 screenshot; Timetables' CSS pins 32x32 at
  `P/timetables_plugin.css.lua:1469-1482`, but in game its tile is as big as the layers button). Problem
  Radar's badge is wider (dot + count). Each plugin's root rule (`R::<Plugin> { gravity }`) sets
  `margin = { 1, 1, 2, 1 }`, the base layers button's (`B/layers/layers.css.lua:44-55`) that Timetables copies
  onto its ToggleButton (`P/timetables_plugin.css.lua:1469-1476`); 2026-10-13. Our old 3 px per side showed a
  wide gap, and no margin made ours touch (user screenshots 2026-10-13).
- `value` = window / panel open, synced in the plugin's `react.onStep` (main thread), so it releases however
  the window closes. `onValueChange` toggles.
- Problem Radar is the exception: its values are { "Text", "Tile" } and the tile holds no icon, only the
  worst-tier dot and the count (user's choice, 2026-10-12); its content is pinned to 24 px tall inline (the icon height; `size` excludes padding), so the tile is 40 px like the others.
- Icons: white 48x48 masks (`@2x.tga`), `tools/render_icon_ridge.py` (map icon: `tools/render_icon_square_better_minimap.py`).
- Layer window offset: see the next section.

## Layer window offset (built 2026-10-12, not yet tested in game)

The base data layer windows (`#menu.layers.window`, margin top 30, `B/layers/layers.css.lua:89-120`) open
under the mod button row, so any mod button covers their title. Each of the five button mods' stylesheets
has an identical "LAYER WINDOW OFFSET" block (only `ME` differs) adding 4 rules: `Window#menu.layers.window`
margin top 72 (gamepad `!input-controller` 92), plus the HUD filter window's two rules repeated with its base
margin (430) so ours don't move it. The `Window` element raises specificity over the base selectors.

Only one copy loads: each mod ships `content/square_ridge/marker.gres.lua` (`gui_res`, `{ squareRidge = true }`),
and a stylesheet adds the rules only if no mod before it in the fixed list (Better Minimap, Problem Radar,
Industry Flows, Supply Gaps, Stress Test, Photo Mode) has its marker found (`api.gui.genericRep.find`, in `pcall`).
A new mod goes at the end of the list: each mod only reads the entries before itself, so the older mods' copies
of the list don't need the new name. Offline simulation of the first 31 combinations (five mods): exactly 4 rules
each time. stdout shows `[SQ ridge] layer window offset:
added by <mod>` / `skipped in <mod> (added by <mod>)`.

To check in game: the windows move (Infrastructure, Traffic, HUD filter, a gamepad if possible); with two or
more of the mods on, one "added by" line and "skipped" lines for the rest. Assumptions under test: a mod rule
can beat a base rule by specificity; a disabled mod's marker isn't found. If it fails: remove the block and
the marker from all five (revert).

## Window kit: proposal

What makes Timetables' window look native, and its cost:

| Element | How Timetables does it | Rules |
|---|---|---|
| Tabs | plain `builtin.TabWidget` (`orientation = North`) + `TabWidgetChild{ indicator = TextView{class="font-scale-tab-widget-indicator"}, item = builtin.Component{layout=...} }` (`P/timetables_plugin.script.tl:199,413-445`); base look (`B/main/builtin.css.lua:738-830`) | 0 (+1 for `TabWidget { margin 8 }`) |
| "Sunken" cards | not sunken: the base entity-window card, a `builtin.Component` with nine-patch `card_surface.tga` tinted `BaseMedium` + `card_contour.tga` tinted `BaseVeryLight`, padding 6, margin 3 (`P/timetables_plugin.css.lua:119-165`; base source `B/main/content_card.css.lua:154-178` (+ outline :34-42); `entity_window.css.lua:74-100` is the button skin inside entity windows, not the card). Darker than the window body, so it reads as sunken. Same values as the base line manager panels (`B/line_vehicle_mgmt/line_vehicle_mgmt.css.lua:170-188`) | 0 inline (`api.gui.NinePatch` in `meta.styleSheet`; verified in game 2026-10-14) |
| Headings | `TextView` class `font-scale-headline` (base, `B/main/font_scaling.css.lua:75`) above the card, padding {2,0,4,6} | 0 inline |
| Rows | `builtin.List`; zebra `backgroundColor = NeutralLightest` at alpha 0.05, selected `AccentDark` at `transparency.Low`, hover `NeutralLightest` at `VeryHigh` (`P/timetables_plugin.css.lua:1239-1290`) | 0: zebra / selected inline; hover and selection are already painted by the base `List::Item` (`B/main/builtin.css.lua:1387-1401`) |
| Widths | pinned size/min/max per column | 0 inline `size` |
| Window | padding on a content class, never on the Window (keeps the close button in the corner, `P/timetables_plugin.css.lua:31-37`) | already our pattern |

Full element-by-element review with the zero-rule way for each (2026-10-14): `plans/ui_style/TIMETABLES_REVIEW.md`.

Timetables itself adds ~187 rules (160 `a(` calls), ~90% of the ~200-rule crash budget
(`docs/findings.md` "Load crash above ~200 mod stylesheet rules"); only ~12 are the look, the rest pin
specific controls. Our kit: tabs + headings + zebra/selected inline, **1-2 rules per mod with windows** (card,
optional hover); with the inline card, 0-1.

Candidates: Problem Radar (already tabs; alert list -> cards + zebra), Line Manager Plus (incl. the rate
matcher), Stress Test (tabs; form sections -> cards), Supply Gaps, Industry Flows, Better Minimap's filter window.

Open questions (one in-game probe answers both):
- Can the card's `backgroundImage1` / `borderImage` be set inline? **Yes, verified in game 2026-10-14** (Problem Radar fleet window; docs/findings/gui.md "Native cards and button padding set inline"): 0 rules per mod.
  in-game confirmation:** `api.gui.StyleSheet` has `backgroundImage1` / `backgroundImage2` / `borderImage` of type
  `api.gui.NinePatch` (`fileName`, `horizontal`, `vertical`, ...; `.cache/game/api/tealdef/api/gui.d.tl`), and the
  base sets one through `meta.styleSheet` (`B/line_vehicle_mgmt/vehicle_react_util.tl:95-105`, via
  `styleutil.makeStyle{ backgroundImage1 = ... }`; `makeStyle` has no `borderImage` key, so set `st.borderImage`
  directly). The slices are Lua tables, as the base assigns tables to vector fields
  (`vehicle_store_window.tl:4045` `config.vehicleGroups = { 1 }`). First use: Problem Radar's fleet window
  (`radar_inline.tl` `cardSheet`, with a plain-colour fallback if the binding refuses; `plans/square_problem_radar/TESTING.md` §0b).
- Do identical rules from several mods count separately toward the ~200 limit? (Assume yes.)

Next step: try the kit in one window (Problem Radar), check it in game, then roll out.
