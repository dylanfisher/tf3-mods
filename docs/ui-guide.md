# UI guide: windows, buttons and controls in our mods

One look across every square mod. **Default (base game) entities first, always** (user 2026-10-14): before designing
any part of a window, find how the base game builds it and reuse that: base `builtin.*` widgets, base recipes and
util modules (`.cache/game/base/content/gui/**`), base CSS classes, and the base looks (entity-window cards,
buttons, window surface) applied inline. Our own look or our own class only when the game has nothing for it,
and then without adding stylesheet rules where an inline style or a shared block does (see Stylesheets).
Modelled on Timetables (`celmi_timetables`, featured by Urban Games), minus its ~187 rules. Background, measurements and the window-kit research:
`plans/ui_style/PLAN.md`. Crash and API facts behind these rules: `docs/findings/gui.md`. When a mod's GUI and this
guide disagree, fix the stale side (CLAUDE.md "Conventions").

Status: rules from user feedback on Photo Mode (2026-10-12/13; the spacing mechanism corrected in round 6, padding
and the option-set pattern in round 8) plus the existing kit. Exact numbers marked
*(tune)* are the current choice, not yet confirmed in game across mods.

## Top-bar button

- `::MainModButtonAreaExtension` plugin, base `builtin.ToggleButton`, our white 24 px icon, 8 px padding (the base
  default, a 40 px tile like the layers button), no inline colour. Pressed while the mod's window is open.
- Plugin root `margin = { 1, 1, 2, 1 }`: the base layers button's margin, as Timetables sets it on its button
  (on our root because inline styles take no margin; the root holds only the button).
- mod.json param `hudButtonStyle` (Text / Icon, default Icon).
- A state that outlives the window (e.g. Photo Mode's High graphics mode) shows as a thin green contour
  (`borderColor` = the game's `Ok` colour) and a tooltip line, never by tinting the icon. Text style: the label
  turns green with a short suffix ("Photo: HQ").
- The button only opens / closes the window. Expensive or risky actions (graphics switches) live inside the
  window behind their own control.

## Windows

- Base `builtin.Window` through `platformWindow` (console rejects fields such as `closable`;
  `docs/findings/gui.md`). A Window wrapper's render returns the Window and calls no react hooks
  (`react.setMouseTransparent` in one crashed the game, `docs/findings/map-camera.md` "Full-screen overlay").
- **Controller (console players):** the Window gets `autoFocusOnBecomingVisible = true` and its content
  `meta = { forceFocusable = true }`; the content recipe handles `IA_MENU_BACK` (close), focuses itself on mount and
  puts its layout in a `gui_react_util.FocusTraversalScope` (inside a BoxLayout: the recipe root stays a layout).
  Reference: LMP `rate_matcher_window.tl` `RateMatcherContent` (rev 8; other windows follow once a PS5 player
  confirms it). `docs/findings/gui.md` "Window fields differ by platform".
- **Narrow:** content 440 px inner width (~460 px with the frame; Photo Mode `CONTENT_W`) *(tune: not yet seen
  in game)*. Rows wrap; nothing may stretch the window across the screen. Size from the longest translated label
  (de/ru ~40% longer, CJK wide); wrap rather than clip.
- **A FlowLayout needs a fixed-width parent:** its preferred width is all items on one line, so a bare
  `FlowLayout` widens the window instead of wrapping (Photo Mode: ~1400 px). Put it in
  `builtin.Component{ meta = { styleSheet = <size {W, -1}> }, layout = builtin.FlowLayout{...} }`, as the base
  vehicle window's cargo icons (`vehicle_eow.script.tl` VehicleInfoCargoIcons). Photo Mode: W = 424 inside a 440
  px content *(to verify in game)*.
- Padding on a Component around the content (inline `padding`), never on the Window itself (keeps the close
  button in the corner) and never on a layout (see Spacing).
- Height: at least 92 px (shorter frames draw broken).
- Tabs: plain `builtin.TabWidget` + `TabWidgetChild`, indicator text class `font-scale-tab-widget-indicator`.
  The indicator row never wraps and each indicator has 18 + 18 px padding (base `TabWidget::Indicator`): in a
  ~440 px window five short text labels are the most (measured with Lato at 16-21 px: Photo Mode's five already
  took 405-475 px in English, 506-613 px in nl). More tabs: icon indicators (a base 24 px icon from `gui.zip`
  in an `ImageView` with the tab name as `tooltip`, as base `town.tl`'s back tab), 60 px each, never a wider
  window (Photo Mode round 11, six tabs: 360 px; round 12, seven: 420 of the 424 px inside the content's padding,
  the most 24 px icons hold). Eight tabs: 16 px icons, 8 x (16 + 36) = 416 px (Photo Mode round 20: the Animals
  tab; an inline StyleSheet has no margin to trim the indicator's padding, and a class rule costs one of the ~200).
- Window-wide switches that outlive the window (Photo Mode's High graphics mode, Hide labels) go on a
  **Settings** tab, the last one, with the base gear icon (`::/gui/menu/icons/settings.tga`, the mod settings'
  icon in `mod_selector_page.tl`), not in the footer (user, Photo Mode round 12). Saved presets of the window's
  own state (Photo Mode's saved setups, round 16) go there too, above the switches: a dropdown of the names (each
  item's tooltip says what it holds), a grid of the actions (Load, Save new, Overwrite, Rename, Delete) and the
  name field of the saved views while one is named.
- **No tabs inside a tab** unless a section won't do: the base nests TabWidgets (construction menu, town window)
  but styles every inner one with rules of its own; unstyled, each level adds the 8 px page padding and a frame,
  and its indicator row needs room of its own (`docs/findings/gui.md` "Nested TabWidgets"). A heading and a
  section cost no rules.
- **Cards** (verified in game 2026-10-14: Problem Radar's fleet window, user screenshot, session `2026-10-14_0753_sqrl-sqsg`): group a window's panels in the base
  entity-window card, set inline, zero rules. A `builtin.Component{ meta = { styleSheet = card }, layout = column }`
  with `card = styleutil.makeStyle{ size = { W, -1 }, backgroundImage1 = surface, backgroundColor1 = c.BaseMedium,
  borderColor = c.BaseVeryLight }`, then `card.borderImage = contour` (`makeStyle` has no `borderImage` key) and
  padding 6 / 8. `surface` / `contour`: `api.gui.NinePatch.new()` with `fileName =
  "::/gui/entity_window/design/card_surface.tga"` / `card_contour.tga`, `horizontal = vertical = { 0, 6, 26, 32 }`
  (the base line manager panels' values, `line_vehicle_mgmt.css.lua:170-188`, as Timetables). Build them in a
  `pcall` and fall back to a plain `backgroundColor` (Problem Radar `radar_inline.tl` `cardSheet`). The heading
  (`font-scale-headline`) goes above the card, no divider inside. Cards side by side of equal height with their
  content at the top: base class `vertical-spacer` on each card (stretches it to the row) and a
  `builtin.Component{ meta = { class = "vertical-spacer" } }` after the content (as the base loan cards). A base
  widget whose rule grows it (`ProgressBar` has `gravity = { -1, -1 }`) goes in a row of its own inside such a card.
  Table rows in a card: fixed inline width + padding, odd rows `NeutralLightest` at alpha 0.05 (Timetables' zebra).
- **A card in a base entity window** (a `react-plugin` on `::TownEowExtensionPoint` etc.; Organic Towns' town card,
  2026-10-17: first pass seen in game, round 2 with thin bars, gaps and visible descriptions *not yet seen*): the
  base `content_card.ContentCard`, and inside it the pieces the base cards use, which the window's own rules already
  style (zero rules; inline style only for the thin bar and the fixed gaps):
  - **Permanent part with a collapsible part:** end it with a right-aligned value (the key / value row below).
    ContentCard draws the collapse triangle at a fixed x near the right edge, straddling the permanent part's bottom
    border (`content_card.tl:318-337`, `content_card.css.lua:139` margin 358); the base cards keep a value above it
    (Line "Transported": the value; Town Level: the growth state). A lone left-aligned line leaves it in an empty
    corner. Nothing else positions it (no class, padding or wrapper on the base permanent widgets).
  - **Key / value row:** horizontal BoxLayout `{ TextView font-scale-body, gui_react_util.makeHorizontalSpacer(),
    value }` (`line_eow.script.tl:80-97`). An explanation of the value goes into the row's tooltip, as the base cards
    do (and visibly under it, see Descriptions); short values only (a long key + value pair doesn't wrap). As the
    permanent part it gets the base card's own vertical padding (InfoCalloutWrapper `card-formatting` 6 / 10,
    `content_card.css.lua:54-57`), the same as the Line "Transported" row (body TextViews both).
  - **Bars:** thin, as the Town Level bar: a `builtin.ProgressBar` (class `font-scale-annotation`) in a horizontal
    BoxLayout of its own, with an inline sheet `size = { -1, 10 }`, the fill colour and the Town Level bar's
    background (BaseVeryLight at VeryLow, `entity_window.css.lua:582-597`). The base thin bars are styled only under
    their own recipes (`R::TownLevelWidget` 8 px, `R::PersonCapacityWidget` 10 px, `:846`); 10 px because an inline
    sheet has no `mask` and the builtin mask's 5 px corners need it. Never `entity_window_util.ProgressDisplay` in a
    card: it is 25 px tall (`:1022-1025`, a heavy bar in the user's screenshot 2026-10-17) and its `extraValue` only
    shows as a lighter tip when above the value, nothing when below. A target goes on the bar as the base
    threshold mark (`thresholds = { aim }`, `builtin.css.lua:1600-1606`: a 1 px line, lighter before the fill reaches
    it, darker after: reads both ways) and in the row above as "41% → 45%". Numbers in the row above or the
    tooltip, not as `text` on the bar.
  - **Descriptions:** visibly, under their row in `font-scale-annotation` (the base secondary line,
    `industry_react_util.tl:589-600`, `warehouse_eow.script.tl:120`; no grey class exists), and in the row's tooltip.
    Don't repeat the permanent part's values in the body: show what explains them.
  - **Sections:** a `font-scale-headline` TextView, and between sections
    `builtin.Component{ meta = { class = "card-children-separator" } }` (the base line between a card's entries,
    `content_card.css.lua:59`; any Component inside the card's InfoCalloutWrapper).
  - **Gaps:** the card body's layouts keep the 2 px default gap (no base rule spaces them), which leaves rows, bars
    and sentences nearly touching. Fixed-gap spacers (`builtin.Component` with an inline `size = { 1, h }`): 4 px
    under a headline and on both sides of a separator, 3 px between a row and its bar or between plain rows, 6 px
    between groups (Organic Towns `ot_card.gapBefore`). A description sits right under its row.
  - **Explanations and empty states:** `content_card.makeInfoHint(text, true)` (`industry_eow.script.tl:357`).
  - **Links to another entity:** a plain `builtin.Button` (no `secondary`, no inline padding: "R::EntityWindowContent
    Button" styles it) holding the entity's icon + a body TextView, `onClick` `react.fireEvent(nil, "selectEntity",
    { entity = id, stack = true })` (`sim_person_eow.script.tl:115-131`); a row of them in a FlowLayout.
- Remember the window position where the player expects it (`AppConfig.mainMenuState[modId]`, see Better
  Minimap / Problem Radar).

## Lists, empty states, settings pages

Problem Radar's main window (2026-10-14). **Verified in game 2026-10-14** (user screenshots, round 1 of the main
window, session `2026-10-14_0842_session`): the list in one inline card with zebra rows, the info-hint empty state
with the footer pinned at the bottom, top-aligned settings columns with a card per section, the inline spin box
width. Round 2 fixes (column gaps, end-of-row buttons, fixed settings columns, short labels) *to verify in game*
(`plans/square_problem_radar/TESTING.md` §0c). Zero stylesheet rules beyond what the window already had.

- **A list in a card:** one native card (Cards above) around all rows, never rows straight on the window surface.
  Each row is a `builtin.Component` with an inline fixed width (the card's content width minus the row padding) and
  padding 2 / 4, odd rows the zebra tint; inside it a horizontal layout (with the gap class) holding the row's
  Buttons. Row actions stay sibling Buttons of the main row Button (never nested), so each keeps its own click.
  Keep `meta.localKey` (the item id) on the row Component.
- **`builtin.List` only for rows without inner buttons:** a click on a control inside a List row bubbles into the List
  (Timetables, `TIMETABLES_REVIEW.md`), so rows with Snooze / Upgrade / second-target buttons stay Button rows in a
  card.
- **Optional per-row buttons go at the row's end** (after the last column): a button only some rows have (Problem
  Radar's "↑ Upg", "→") never gets a column of its own near the start, where every other row shows an empty hole
  (round 2: the All tab had fleet rows further down, so every row got the gap). The left columns stay identical on
  every row and tab. Reserve its width in the row budget.
- **No mostly-empty columns:** context that only some rows have (a vehicle's line, a depot) and short attributes
  (the vehicle type) go on a second, dim annotation line under the name, not into columns that stay empty.
- **An inline `size` doesn't clip a TextView:** a longer text runs on past the box into the next cell and the column
  gap disappears (round 2: a long line name ran straight into the detail text; `docs/findings/gui.md`). Inline
  fixed widths only for texts known short in every language; names, details and labels wrap at a fixed width with a
  rule (`minSize = maxSize = { W, -1 }`, `textAutoWrap`), one rule shared by every cell of that width (Problem Radar:
  the name and detail cells share `radar-cell-wrap`).
- **Keep the column gaps when rebuilding rows:** every cell of a row sits in a layout with the gap class, and a
  cell's text must stay inside its width (above); check a long name and a long translation.
- **Give spare width to the text that wraps:** size the wrapping cells from the row budget (row width minus the
  fixed columns, gaps, a typical last column and the end buttons), so most texts fit one line instead of wrapping
  while the row's right part stays empty.
- **Empty state:** the base `content_card.makeInfoHint(text, true)` (card surface tinted Info, info icon, wraps at
  ~350 px; base rules only) as the only child of the same ScrollArea the list uses, so it sits at the top and the
  area still fills the tab. Never a bare message in a layout: it floats to the middle with the footer under it.
- **Footer pinned at the bottom:** the tab page is a column of the list area (a ScrollArea whose class rule has
  `gravity = { -1, -1 }`, one rule for every tab) and the footer. The footer is a Component (inline top padding)
  with a 1 px line as wide as the list's card (inline `size = { W, 1 }` + faint `backgroundColor`), a 4 px spacer
  and the row. A label next to a ToggleButtonGroup gets ~5 px inline top padding (no vertical centring inline).
- **Two-column settings, top-aligned:** each column is a `builtin.Component{ meta = { class = "vertical-spacer" } }`
  (base class: stretches to the row's height) whose layout ends with a `builtin.Component{ meta = { class =
  "vertical-spacer" } }`, so the shorter column starts at the top instead of being centred. In each column a
  heading (`font-scale-headline`) above a card per section. Size the two cards to the page width (page width = the
  content's inline width - 2 x 8 tab padding - 18 px scrollbar room) and put the column with the longest labels on
  the wider side.
- **Table-like rows line up only with fixed-width cells:** put each cell of a column in a `builtin.Component` with an
  inline `size = { W, -1 }` (layout: a vbox with the cell). A wrapping TextView alone takes the width of its
  wrapped lines, and a variable-width cell (a range text) moves everything after it, so the spin boxes sat ~10 px
  apart from row to row (round 2). Each row in a Component with 3 px inline padding above and below: the layouts'
  2 px gap left rows nearly touching.
- **Number rows:** short label (one line in English; the full explanation in the tooltip) in a fixed box ·
  `DoubleSpinBox` with an inline width (`size = { 72, -1 }`, verified; the base adds 4 px padding a side) · the range
  on one dim line in a fixed box ("1-240 min · default 3": the translated range and default joined by " · "). The
  tooltip on label and spin box: the explanation wrapped in code (`radar_hud_model.wrapTooltip`, CJK counted
  double) plus the range.
- **Buttons in settings and footers** (Reset, Unsnooze all): base `secondary` with the inline compact padding, a
  fixed spacer above instead of a margin rule.

## Spacing (the rule users notice first)

- **Nothing touches.** Equal gaps everywhere: 6 px between rows of a column, between items of a row and between
  the wrapped lines of a FlowLayout; 12 px from a checkbox's label to the next box in a row of checkboxes (6 px
  reads as touching next to a label). *(tune: Photo Mode round 6, not yet seen in game)*
- **How: CSS `innerSpacing` on a class, never an inline styleSheet on a layout.** An inline `meta.styleSheet` on a
  `builtin.BoxLayout` / `FlowLayout` never applies: react hands a builtin's `meta.styleSheet` to
  `builtin.WithComponentParams` (`gui/main/react.lua` ~375-385), which styles a Component, and a layout isn't one;
  the base game never puts an inline sheet on a layout. Photo Mode rounds 3-5 padded every item, row and the
  footer that way and none of it showed (user screenshot 2026-10-13: rows on rows, the footer on the window edge;
  `docs/findings/gui.md` "Inline styleSheets don't apply to layouts"). The gap between a layout's children is its
  `innerSpacing`, which only a stylesheet rule sets (base `builtin.css.lua` "ToggleButtonGroup!flow FlowLayout",
  "CheckBox BoxLayout!buddy-layout"). So: give the layouts a class (`meta = { class = "xx-gap" }` on the
  BoxLayout / FlowLayout itself) and add one rule per spacing, without an element name so it covers both layout
  kinds: `a("R::MyContent !xx-gap", { innerSpacing = { 6, 6 } })`. Photo Mode needs three rules for the whole
  window (`sqpm-gap` 6/6, `sqpm-checks` 12/6, `sqpm-content` 8/8;
  `mods/square_photo_mode/content/photo_mode/gui/pm_button.css.lua`). No per-item wrappers: innerSpacing sits
  between items, so a wrapped line starts flush. `tests/square_photo_mode/test_window.lua` checks that no layout
  carries an inline styleSheet and that every class has its rule.
- **Padding goes on a Component, never on a layout** (not inline, not by a class rule: Photo Mode round 8, the
  root BoxLayout's class padding never showed, `docs/findings/gui.md` "Padding applies to Components, not
  layouts"). The recipe returns a layout whose one child is `builtin.Component{ meta = { styleSheet = st },
  layout = column }` with `st.padding = api.type.Vec4f.new(8, 8, 8, 8)`.
- What inline styleSheets do apply to: Components, TextViews, Buttons, ImageViews (size, padding, colours;
  `docs/findings/gui.md` "DataTable column weights, inline sizes on recipe calls"), and a recipe call's `meta`
  (its R:: node). A fixed gap of a few px (e.g. more space above a primary button): a `builtin.Component` with an
  inline `size = { 1, h }` as a spacer.
- Labelled rows (label column + controls): a horizontal BoxLayout with the gap class; labels share one column
  width (120 px, wrapping via a `textAutoWrap` class rule).
- Sections: a heading (`font-scale-headline`) above each group, a few px more above it than the rows' gap (inline
  padding on the heading TextView).
- Footer and status areas never sit on the window edge: the root Component's padding (8 px on all sides) plus the
  footer's own Component padded like the tab page (8 px left and right: the base `TabWidget::Content` pads its
  page by 8), so the footer's rows start where the tab content starts. A separator line (a Component with an
  inline `size = { W, 1 }` and a faint `backgroundColor`) above the footer, inside its padded Component.

## Controls

| Need | Widget | Notes |
|---|---|---|
| Action | base `builtin.Button` with `meta.class = "secondary, xx-small"`: the base outlined button (`default.css.lua` `Button!secondary`: the accent contour, base hover / pressed / disabled) with compact padding (one class rule, `padding = { 4, 6, 4, 6 }`), text `font-scale-body` | Never the plain base Button: it is borderless ("ghost") with 8 px padding, a tall block that reads as rows on rows (user, Photo Mode round 8: "if they just had outlines it would be better"). Row icon buttons the same. Many actions: see "Option sets". |
| Action, zero rules | base `secondary` / `primary` Button with the compact padding as an inline `meta.styleSheet` (`padding` only) | Problem Radar's fleet window (verified in game 2026-10-14): no `xx-small` rule. Only `padding`: an inline colour would override the base hover / pressed states. |
| Primary action (Start tour) | base `builtin.Button` with `meta.class = "primary"` (base `default.css.lua` `Button!primary`: accent background), body text | Must look like a button, never bold plain text. No inline size or font on the Button (Photo Mode's inline size + title font showed as plain bold text); an inline sheet with only `padding` keeps the base look (Problem Radar's ridge tile ToggleButton; the fleet window's buttons to verify in game). Natural width, left-aligned (inline sheets can't centre: no `gravity`). |
| On / off setting | base `builtin.CheckBox` with a label | Also for modes the player toggles (Hide labels, High graphics mode). Not a plain button. Exception: a construction-toolbar on / off whose state the mod must show before any click (twin Yes / No toggles, "Construction toolbar"). |
| One of a few (2-4 short labels) | base `builtin.ToggleButtonGroup{ layout = "Flow" }`, each option `meta.class` the compact class | Separate buttons with the base 4 px `innerSpacing` (`ToggleButtonGroup!flow FlowLayout`) that wrap; the selected one stays highlighted. Inside a fixed-width box (see Windows). The default "Horizontal" layout joins the buttons into one segmented bar. |
| One of many (5+, or long labels) | base `builtin.ComboBox{ value, items = { builtin.ComboBoxItem{ value, content = TextView } }, onValueChange }` | One line instead of rows of options (as the base mod settings, `script_param_util.tl`, and the cargo layer). Each item's TextView carries its tooltip (the base mod settings do the same); the closed box shows the selected item's tooltip. Values as strings (`tostring(i)`). Photo Mode's Tour mode. When the player flips through the options to compare them (Photo Mode's looks, round 15), a compact `<` and `>` button either side of the box steps to the previous / next option, wrapping round at both ends (tooltips "Previous look." / "Next look."). |
| Per-row actions in a list | small icon buttons (base icons, e.g. the mod selector's up / down / trash) | Disabled state visibly greyed. |
| Text entry | base `TextInputField` (`displayOnly` for read-only); numbers: `DoubleSpinBox` | `FocusTextInputField` / `FocusNumberInputField` are deprecated in the base (`gui_react_util.d.tl`). |
| Step a value (percentage, a few steps) | compact outlined `builtin.Button`s (as Action) holding the base spin box arrows as a 16 px `ImageView` (`::/gui/builtin/spinbox/arrow_left.tga` / `arrow_right.tga`, the icons of the base `DoubleSpinBox`), the value between them, with the base's small-button contour set inline (`meta.styleSheet`: `borderImage` / `backgroundImage1` = `compact_contour` / `compact_surface` NinePatches, slices `{ 0, 5, 7, 12 }`; no stylesheet rule). Never a one-character text button (`<`, `>`), and not the default 30 px contour: on a button this small its 9 px corners are most of the edge and the sides show a notch (`docs/findings/gui.md` "The base button contour") | Photo Mode's step buttons (Light / Weather sliders, look arrows; round 18, compact contour round 19, the notch gone in game round 20). Each arrow has a tooltip naming the step ("10 minutes later."). |
| A value over a wide range (time of day, date, angle) | base `builtin.Slider{ horizontal = true }` in **a recipe of its own** with arrow step buttons (the row above) either side and the value text after it, in the row's control box (a horizontal BoxLayout with the gap class) | The slider's `onValueChange` fires for every value passed while dragged (`docs/findings/gui.md` "builtin.Slider"), and a window that re-renders on every change can't keep up. So (round 15, Photo Mode's Light tab, `gui/pm_slider.lua`): the recipe keeps the dragged value in its own `react.useState` (a move re-renders only that row), writes go out throttled and quiet (at most every 80 ms, the last value trailing, no log / save / window refresh), and the gesture ends with one normal write at the mouse release (`react.onMouseEvent`, as the base construction slider) or 400 ms after the last move. Integer ranges (minutes, days, degrees). Tooltips on the slider, its value text and both arrows. *(tune: not yet seen in game)* |
| Long lists | `ScrollArea{ content = Component{ layout = ... } }` | Never a layout as ScrollArea content. |

- **Small buttons (under about 30 px wide or high) get the compact contour, or their edges show a notch.** The base
  draws every Button with the 30 px `default_contour` 9-slice (9 px corners): on a smaller button the two rounded
  corners meet in the middle of the side edges and leave a dent (Photo Mode's 24 x 28 px arrow buttons, user
  screenshot 2026-10-14). Set the base's small-button contour inline, as the base TextInputField and DoubleSpinBox
  +/- do: `meta.styleSheet` with `borderImage` and `backgroundImage1` = `api.gui.NinePatch` of
  `::/gui/builtin/button/compact_contour.tga` / `compact_surface.tga`, slices `{ 0, 5, 7, 12 }` both ways; keep the
  `secondary` class for the colours. No stylesheet rule. Verified gone in game (Photo Mode round 20). Photo Mode's
  `compactStyle()` in `gui/pm_window.lua` builds it; findings `gui.md` "The base button contour".
- Every control has a tooltip, wrapped per CLAUDE.md "Tooltips": every Button, ToggleButton, CheckBox, Slider, step
  button, row action, **each option of a ToggleButtonGroup** (its own `meta.tooltip`; the base group copies
  it onto the option's ToggleButton) and each ComboBox item (on its TextView). A labelled row's label gets one too, saying what the row chooses. Photo
  Mode's `tests/square_photo_mode/test_window.lua` audits every tab (user 2026-10-13: tooltips showed only on the
  one option that had one).
- A control that hides the whole game UI names the way back in its tooltip, and the way back must not need the
  UI. Prefer the game's own free camera (base `FreeCamTool` pushed on the default tool stack: the game hides its
  UI and Esc / back pops the tool natively; Photo Mode's "Free camera", `gui/pm_hud.lua`). Hiding the UI root
  yourself (Photo Mode's tours) also works: Esc opened the pause menu while it was hidden
  (`docs/findings/gui.md` "Input actions don't reach a hidden GameUIRoot", update 2026-10-13); restore on the
  pause menu, take the pause key (Space) too, and restore at every game start.
- Footer: the actions wanted on every tab (Photo Mode: Free camera, the screenshot buttons) below
  the tab content, under a separator line, inset like the tab content (Spacing), then the status line. Settings
  checkboxes go on a Settings tab (Windows).
- **Right-aligning** a group in a row (Photo Mode round 12 footer; to verify in game): a horizontal `BoxLayout`
  (gap class) in a `Component` of a fixed inline width, with the base `gui_react_util.makeHorizontalSpacer()`
  between the groups (a Component of class `horizontal-spacer`, base `default.css.lua` `gravity = { -1, 0 }`: it
  takes the spare width), as the base calendar's Environment row (`game_bar_widgets.tl`). No rule of our own: inline
  sheets have no `gravity`. A BoxLayout never wraps, so the part that may grow with a translation goes in a
  fixed-width `FlowLayout` box (it wraps there) and the fixed part is sized for the widest language; measure every
  language at body 14 / 17 / 19 px.

## Construction toolbar (tool windows in the construction menu)

Tools that live in the construction menu (Smart Lanes, Bulk Bulldozer) get their controls as toolbar params,
which the menu draws as buttons or checkboxes (`script_param_util.tl`). Any **status / description text** there (selection,
"Nothing selected" plus the hint, results, lane status) uses the shared tool info style:

- A one-value `Button` param kept `"Disabled"` by its `checkEnabledFn`, `hideLabel = true`, in its **own group**
  with the id `sq-tool-info` (the class the style targets; dashes only, underscores silently break a selector,
  `docs/findings/gui.md` "CSS class names"). Its `makeCompactButtonFn` returns a self-updating recipe: a vertical
  `BoxLayout` of TextViews, `font-scale-body` for the main line and `font-scale-annotation` for the hint.
- The style is the "TOOL INFO STYLE" block in each tool's stylesheet (`sl_tool.css.lua`, `bulk_bulldozer.css.lua`):
  4 rules (invisible fill and contour, `gravity = { 0, 0.5 }`, `NeutralVeryLight` text wrapping at 280 px) that
  turn the grey disabled button into plain left-aligned text. **Only the first active tool adds them** (each ships
  `content/square_tool_info/marker.gres.lua`; the blocks are identical except `ME`), so the cost stays 4 rules
  however many tools are on. A new tool copies the block and the marker and goes at the end of
  `SQ_TOOL_INFO_MODS`; `tests/<mod>/test_tool_info_css.lua` checks the count and that the blocks match.
  A separate copy per mod pushed a full mod set over the rule cap and crashed a new game (2026-10-14).
- Other colours (Smart Lanes' green / amber lane status) go inline (`meta.styleSheet = styleutil.makeStyle{ color }`),
  not as more rules.
- Never leave status text as a bare grey disabled button (user 2026-10-13). Action buttons stay in their own group
  above it.
- **Hide what has nothing to do, gray only what is waiting** (user 2026-10-16, Smart Lanes rev 8 v3; replaces "rows
  only when relevant, gray with a reason inside them", 2026-10-14): a button whose click would change nothing for the
  selection (not handled, nothing to change, nothing to reset, no junction) is `"Hidden"` from `checkEnabledFn`; a
  row whose buttons are all hidden disappears (the menu drops hidden params before grouping: no gap or separator
  line). The status / badge text must say why (the lane status, "not handled: <reason>", "nothing to change here"),
  so never put a fact only in a hidden button's reason. `"Disabled"` (grayed) is for a passing state only (a change
  landing, a run elsewhere), and for a group that belongs together and stays put (Smart Lanes' light row at a lit
  junction; but a button whose feature is already on hides and the status checks it: Smart lights once set, the
  badge "√ Smart lanes | √ Smart lights", user 2026-10-16). A grayed button says why: the param's own `tooltip` can't change at runtime (`docs/findings/gui.md`
  "Construction toolbar params"), so put the reason in the tooltip of the `makeCompactButtonFn` content (a small
  recipe whose TextView `meta.tooltip` is "Grayed out: <reason>" above the static text, polled every step), and let
  the static tooltip say when it is shown / grayed too (the in-game display of a tooltip inside a disabled button is
  unverified). Compute states from the selection and the tool's own state, never from the hover, and cache what's
  expensive (the menu asks every step and re-lays the bar when a result changes).
- **Small toolbar buttons** (user 2026-10-16: the size of the Yes / No toggle): give a one-value action `Button` param
  `numbers = { 1 }`. The menu then draws it as a base ToggleButtonGroup with one button (the toggle's widget), which
  escapes the bar's 32 x 32 px minimum on `ToggleButton!right-parameters`; no stylesheet rule, clicks still reach
  `onChangeFn`, `makeCompactButtonFn` content and "Disabled" / "Hidden" unchanged. Read from the game files, not yet
  verified in game (`docs/findings/gui.md` "Construction toolbar params", Smart Lanes TESTING.md "Toolbar rows").
- **On / off modes:** a CheckBox param (`ScriptParamType.CheckBox`, `values = { _("No"), _("Yes") }`, 1 / 2, as the
  base "Follow Terrain") draws the base CheckBox with the param's name as its label (`hideLabel = true` to share a
  row with buttons). Only for a real persistent mode: Smart Lanes' "Lights only" was one and went back to a button
  (user 2026-10-14: a checked box that changes what another button does was one click too many, and it could not be
  unchecked once the row was hidden). Keep the mode in the tool's state from `onChangeFn` and set
  `resetOnMenuClose` / `resetOnDefinitionChange` when it should end with the tool.
- **On / off state of the selected object** (Smart Lanes' "Keep timing adjusted", per junction): the exception to
  "on / off is a CheckBox". Its shown value must follow the selection from the first frame, and a param's shown value
  can only be set through the params api that `onChangeFn` hands over at the first click (`checkEnabledFn` gets none:
  `docs/findings/gui.md` "Construction toolbar params"), so a CheckBox shows its default, possibly wrong, until then.
  Use the base Yes / No toggle (a two-value `Button` param, `values = { _("Yes"), _("No") }`, the label shown, as the
  street builder's "Underground") as **twin params**: same label, values, group and place, one with default Yes shown
  (`checkEnabledFn`) when the object is on, one with default No when it is off, the other "Hidden". Before any click
  each shows its default, the truth by construction. Take the clicked side as the intent (Yes = on, No = off, never
  "toggle"; the side in force changes nothing), keep the api from `onChangeFn` and from then on write both twins'
  stored values (`getStoredValues(getCategory())[key]`) from the object's state every step, so a twin clicked earlier
  never shows a stale side. Hidden params' values leave the current values: never read these keys in the tool's
  action. Say the state in the status text too.
- **Settings in the toolbar** (Smart Lanes' in-game settings panel, `sl_settingsui.lua`; unverified in game,
  plans/square_smart_lanes/TESTING.md "SP"): labelled params in one group of their own (labelled params of one group
  stack vertically), `displayMode` Vertical (label above the control: long labels fit the 314 px bar), On / Off and a
  few short values as the base toggle (a `makeCompactButtonFn` BoxLayout when a value may pass the bar's 50 px text
  box), long values as a ComboBox param (as the base Town Builder). The shown value follows the mod's state without
  twins: `checkEnabledFn` sets `param.defaultIndex` every step (the menu re-reads the default through `getParam`,
  which returns the mod's own table) and, once a click handed the params api, the stored value;
  `preserveValueInAllCategories` shares it between tools.
- **Button size:** the toolbar has one button look, the base `ToggleButton!right-parameters` the base tools use
  (4 px padding, at least 32 x 32 px); `makeCompactButtonFn` sets only its content (keep `font-scale-body` text in a
  BoxLayout so the bar's 50 px TextView rule doesn't clip it). There is no smaller native variant (`displayMode =
  Compact` is a popover button, `secondary` is a `Button` class), so don't style one: it would cost rules.

## Option sets (many choices in a narrow window)

Photo Mode round 8 (user, 2026-10-13: the Subjects tab's rows of borderless buttons were "too cumbersome, need a
better pattern for many options").

- **Many actions** (subjects to jump to, shot presets, light presets): a grid of equal cells. Each cell is a
  compact outlined button (Action above) plus a cell class that fixes the label's width, centres it and lets it
  wrap: `a("R::MyContent !xx-cell TextView", { size = { W, -1 }, textAutoWrap = true, textAlignment = { 0.5, 0.5 } })`.
  The cells go in a `FlowLayout` inside the fixed-width box (Windows), so they wrap by the window width, never by
  a fixed count. Size W so three cells and two gaps fit the row (Photo Mode: 122 + 2 x 6 padding = 134 px, 3 x
  134 + 2 x 6 = 414 of 424). A long translation wraps inside its cell; the line takes the tallest cell's height.
- **On / off moves among them** (Orbit, Wander, Follow, Cockpit): base `ToggleButton`s with the same cell class:
  filled (accent while on), the same size as the action cells.
- **One of many** settings: a ComboBox (Controls). A heading above each group; a dim one-line hint below at most.
- **The primary action** stays the base `primary` button (Controls), never a cell.

## Text

- Body text `font-scale-body`; small hints `font-scale-annotation` only for one short line. Status lines use body
  font in their own padded box, wrap (a `textAutoWrap` rule with a fixed width) and never overlap the window edge.
  "Nothing found" / empty lists: the base info hint (see "Lists, empty states, settings pages").
- Every displayed string through `_()`, in all 13 languages (CLAUDE.md "Translations").

## Stylesheets

- Mod CSS rules are a shared budget (~200 across all mods crash the game, `docs/findings.md`). Inline styles
  first where they apply (Components, TextViews, Buttons; `api.gui.StyleSheet` takes only colours, background,
  border, size, padding, font size and anchor point: no `textAutoWrap`, `maxSize`, `gravity` or `innerSpacing`).
  A rule block that several of our mods need goes in once with a leader marker (the layer window offset, the tool
  info style), never as a copy per mod.
- **Base classes before our own:** before adding a class rule, look for a base class that gives the look
  (`.cache/game/base/content/gui/main/default.css.lua`, `builtin.css.lua`; e.g. `font-scale-body` /
  `font-scale-annotation`, `secondary` / `primary` buttons, `positive` / `warning` / `error` text, `horizontal-spacer`).
  They cost no rules, look native and follow game updates and the text-size setting. Check that the base rule
  doesn't depend on a base parent (`ToggleButtonGroup!flow ...`). Our own class only for a look the game doesn't
  have. Spacing between children (`innerSpacing`) still needs class rules: keep them few and prefer one shared
  leader-marker gap block across our mods over per-window gap classes (`plans/ui_style/TIMETABLES_REVIEW.md`).
- **Inline styles in code:** build each `StyleSheet` once (lazily, in a render) and reuse it; keep the raw values
  (colour tables, sizes) beside it and build new sheets from those. **Never read a sheet's property back**
  (`st.color`): it is a fatal "class is not registered in LuaBridge" error (`docs/findings/gui.md`). Offline tests
  use stub sheets that raise on a read (`tests/square_problem_radar/test_inline.lua`).
- **Turning a rule into inline:** `minSize` = `maxSize` without wrap becomes an inline `size {W, -1}` (minSize alone
  doesn't: a fixed size clips longer translations); a margin becomes padding only on an element without a
  background or border; check the base state rules first (base Buttons have no margin, and their hover / pressed
  states set only `backgroundColor1`, so an inline `padding` is safe, an inline colour on a Button is not).
- **Workflow for every GUI change:** count rules before and after (`make css-rules MODS='<the user's set>'`); keep
  each visual step revertible (`plans/<mod>/<step>.patch`, checked with `git apply -R --check`); compare the result
  with earlier captures at the same scale (`plans/<mod>/shots/`) or the user's screenshots; mark new guide patterns
  "to verify in game" until a screenshot confirms them, then record the confirmation (`docs/findings/gui.md`).
