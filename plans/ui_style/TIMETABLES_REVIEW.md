# Timetables windows: the zero-rule way (review 2026-10-14)

How Timetables (`celmi_timetables`, featured by Urban Games, our native-look reference) builds its windows, and
how we get each look **without adding stylesheet rules** (mod rules are capped: load crash above ~205 across all
mods, `docs/findings.md`). Rule for all our GUI: default (base game) entities first (`docs/ui-guide.md`).

Paths: P = `.cache/subscribed/celmi_timetables/content/timetable/plugins/`, B = `.cache/game/base/content/gui/`.
Timetables' CSS (`P/timetables_plugin.css.lua`): 160 `a(` calls, 187 selectors. About 15 make the look (card 4,
compact button chrome 15 selectors at css:1511-1536, zebra / hover / selected 5, empty state 3, priority toggles 2);
the rest pin sizes and alignment.

Inline `meta.styleSheet` takes only backgroundColor/1/2, backgroundImage1/2 (NinePatch), borderImage, borderWidth,
borderColor, color, size, padding, fontSize, anchorPoint; nothing on layouts; never read a sheet's properties back.

| Element | Timetables | Zero-rule way | Rule? |
|---|---|---|---|
| Window | `builtin.Window{id, title, closeable, autoFocusOnBecomingVisible}` (script.tl:456-463; the field is really `closable`, `B/../scripts/builtin.d.tl:1186-1190`); size + centring by CSS (css:38-42) | `initialX/initialY` (`B/menu/mod_manager_react_util.tl:6014-6024`); size = inline `size` on the content Component | no |
| Content padding | padding 12 on a class that sits on a BoxLayout (lines.script.tl:990) — likely dead (layouts take no padding) | inline `padding` on a wrapping Component | no |
| Tabs | `TabWidget` + `TabWidgetChild`, indicator `font-scale-tab-widget-indicator` (script.tl:413-447); margin 8 rule (css:48-50) | base look (`B/main/builtin.css.lua:740-1066`; `TabWidget::Content` already pads 8 with surface + contour :969-984); margin → a Component around it with inline padding. Base classes `!no-background` / `!no-content` (:985-998) | no |
| Top-bar button | ToggleButton + ImageView, 32/24 px + margin (css:1469-1482) | base ToggleButton (`builtin.css.lua:140-171, 203-240`), margin on our plugin root rule | margin only |
| Headings | `card-title, font-scale-headline` above the card; `card-title` is their rule (css:181-183) | `font-scale-headline` (`B/main/font_scaling.css.lua:75`) + inline padding | no |
| Cards | `card_surface` (BaseMedium) + `card_contour` (BaseVeryLight), slices {0,6,26,32} (css:123-139); margin / padding / gravity 3 more | **inline NinePatch, verified in game 2026-10-14** (`docs/findings/gui.md` "Native cards and button padding set inline"; `square_problem_radar` `radar_inline.tl cardSheet`), or the base `content_card.ContentCard` recipe (below). Gap: a spacer Component with inline `size`. Fill / gravity can't be inline | no |
| List rows | `builtin.List{selectionIndex, keepSelectedVisible, onSelect, onActivate}` (lines:1006-1033); zebra / hover / selected 5 rules (css:1239-1292) | base `List::Item` already paints hover (AccentLight@High) and checked (BaseVeryLight@Low) (`builtin.css.lua:1387-1401`); zebra inline `backgroundColor` NeutralLightest@0.05 on odd rows. Check in game that hover still shows (Timetables found its zebra hid it, css:1258-1263) | no |
| Row padding, status dot | padding rule (css:1381-1383); dot `R::Component!color-dot-view` (widgets.script.tl:56-68) | inline `padding`; the dot is a global base rule (`B/line_vehicle_mgmt/line_vehicle_mgmt.css.lua:281-285`, 14 px), tinted by inline `backgroundColor1` | no |
| Column widths | ~40 size / min / max rules | inline `size {W,-1}` (no min/max, and it doesn't clip: a longer text runs into the next cell, `docs/findings/gui.md`; so truncate in Lua, or a shared wrap rule; `TextView.tooltipWhenClipped`, builtin.d.tl:768-773); real tables: `builtin.DataTable` + `ColumnDesc{weight}` (builtin.d.tl:1140-1185; header, sort, hover, compact cell buttons from base rules `builtin.css.lua:1413-1522`) | no |
| Sortable headers | stripped Buttons + 6 rules (css:361-387) | DataTable `SortButton` / `HeaderItem` (`builtin.css.lua:1465-1512`) | no |
| Buttons | ghost Button + compact nine-patch on 15 classes; sizes pinned | `secondary` / `primary` (`B/main/default.css.lua:77-121`) + inline `padding` (verified 2026-10-14); small buttons: compact NinePatch `compact_surface/contour` {0,5,7,12} inline (to verify) | no |
| Toggle groups | `ToggleButtonGroup` restyled compact (css:960-978) | plain base group is already segmented (`builtin.css.lua:294-490`) | no |
| Filter toggles | ToggleButton + 18 px icon, copied statistics rules | inline padding 0 + inline `size {18,18}` on the ImageView; icons `vehicle_*_18.tga`, `symbol_eye_18.tga` | no |
| ComboBox | `compact = true`, width pinned (css:918-937) | `compact = true` (`builtin.css.lua:636-647, 685-720`); width from an inline-sized wrapper | no |
| Spin boxes | `DoubleSpinBox`; hides the clear "x" (css:1204-1206) | base skin `builtin.css.lua:1187-1283`; **the base rule hiding the x has a typo** (:1238 `TextInputField::Clear]`) | **1, shared** (leader marker) |
| Checkbox in a row | a Button with `checkbox/checked_16.tga` (a CheckBox click bubbles into the List, lines:289-305) | same trick; elsewhere `builtin.CheckBox{label}` | no |
| Empty state | own class, 3 rules (css:1080-1105) | `content_card.makeInfoHint(text, addIcon)` (`B/main/content_card.tl:479-497`; global rules `content_card.css.lua:209-240`: Info card, 380 px, wraps) | no |
| Muted / tone text | NeutralLight colour rules | inline `color`; base `positive` / `negative` / `warning` / `error` / `info` / `success` (+ `-tape`) (`default.css.lua:12-66`) | no |
| Spacers | own stretch class | `gui_react_util.makeHorizontalSpacer()` / `makeVerticalSpacer()`, classes `horizontal-spacer` / `vertical-spacer` (`default.css.lua:124-130`) | no |
| Gaps between children | `innerSpacing` rules | no inline way: fixed-size spacer Components or recipes with their own spacing | **1-2, shared** gap classes |
| Separators | none | ContentCard `separatorBetweenExtraChildren`; elsewhere a Component with inline `size {W,1}` + `backgroundColor` | no |
| Icons | base glyphs (`symbol_locate_20`, `symbol_wrench_20`, carriers `_18`) | inline `size` + `scaling = AutoFit` | no |
| Scrolling | `builtin.List` scrolls itself (`verticalScrollBarPolicy = AsNeeded`) | same | no |
| Tooltips | `meta.tooltip` on every control | same; `tooltipWhenClipped` for truncated text | no |

## Base recipes for whole patterns (zero mod rules)

- `content_card.ContentCard{ title, extraChildrenPermanent, separatorBetweenExtraChildren, recipeAndParamPermanent =
  content_card.makeRecipeAndParam(R, p), recipeAndParamCollapsible, collapsibleExpanded, setCollapsibleExpanded,
  gameCtx, showOnRightSide }` (`B/main/content_card.d.tl`, render `content_card.tl:207-455`): headline with the
  `window_card_heading_decor.tga` line, card surface + contour, padding 6/10, optional collapse. Used by the base in a
  plain window (`B/line_vehicle_mgmt/cargofilter_window.tl:690-800`) and by Timetables (`P/timetables_eow.script.tl:302-318`).
  Helper `makeContentCardsCollapsibleFunctions(state, onlyOne)`.
- `content_card.makeInfoHint(text, addIcon)`: info / empty-state bubble that wraps.
- `gui_react_util.IconLabelIndicator{iconPath, label, richLabel, labelFontColor, labelMode, tooltip, indicatorIconPath}`
  / `makeContentLabelIndictator`: entity-window icon + value rows (global classes `gui_react_util.css.lua:14-50`).
- `entity_window_util.ActionButtonBar`, `EntityWindowButton`, `SendCommandButton` (`B/entity_window/entity_window_util.d.tl`);
  their skin applies only inside `R::EntityWindowContent`.
- `builtin.DataTable` + `ColumnDesc{weight, getCompareValue, recipe}`.
- `vehicle_react_util.VehicleWidget{vehicleEntities}`, `cargo_react_util.makeCargoIcon(id, "iconSizeTextIcon, cargo-icon-only")`.
- `statistics_react_util.createCarrierCategoryFilter / createSearchField`: their look is scoped to the statistics window.

## Takeaways

1. Grouped sections: prefer `ContentCard` (or the verified inline card) over hand-made panels.
2. Lists: `builtin.List`, base hover and selection, inline 0.05 zebra.
3. Buttons: `secondary` / `primary` + inline padding; compact NinePatch inline for small buttons (to verify).
4. ComboBox `compact = true` and the plain ToggleButtonGroup give compact form controls for free.
5. Sortable tables: `DataTable` + `ColumnDesc{weight}` instead of width rules and hand-made headers.
6. Empty states: `content_card.makeInfoHint` (wraps without a rule).
7. A shared leader-marker block across our mods for the few real needs: the DoubleSpinBox clear-x fix and 1-2 gap
   classes (2-3 rules in total, not per mod).
