// Gallery slides per mod: _metadata/1-<hash>.png, 2-<hash>.png, ... in slide order.
// Captures live in plans/<modId>/shots/ (never shipped); crop = [x, y, w, h] in capture pixels
// (5120x2880 Retina full-screen). Layouts (see slide.js):
//   single  { src, crop }
//   inset   { main: {src, crop}, inset: {src, crop}, insetW, at: 'tl'|'tr'|'bl'|'br' }
//   wipe    { before, after, crop, labels: [before, after], beforeCrop? }  same camera, 45° split
//           (beforeCrop re-frames "before" when the camera moved a little between captures;
//            split: share of the diagonal given to "before", default 0.5; darkChips: both labels dark)
//   stack   { items: [{src, crop}, {src, crop}], labels }      same UI, two states
//   table   { head: [col1, col2], rows: [[a, b], ...] }         text card, no capture
//   collage { items: [{src, crop, x, y, w, rot, label}], print? }  free placement (centre x/y, width in slide px)
//   any layout: badges: [{ big, small, x, y, w }] result cards; table: { head, rows, top } a table card on top
// title: 2-4 words, sub: one short line. English only.

Square.slides('square_bigger_line_dots', [
  { title: 'Spot every line', sub: 'Line dots grow from 7 to 12 px above every stop',
    media: { src: '01-columbus.jpg', crop: [1880, 800, 1680, 1240] } },
  { title: 'Busy stops, still clear', sub: 'Every line at a glance, and easier to click',
    media: { src: '03-busy-station.jpg', crop: [2080, 480, 1920, 1280] } },
]);

Square.slides('square_industry_flows', [
  { title: 'All flows at once', sub: 'Every industry of one type, in one view',
    media: { layout: 'inset', at: 'bl', insetW: 400,
             main: { src: '05-livestock-all.jpg', crop: [1200, 160, 3920, 2520] },
             inset: { src: '05-livestock-all.jpg', crop: [56, 720, 1104, 1168] } } },
  { title: 'Inputs, outputs or both', sub: 'Faded arrows mark possible links',
    media: { layout: 'inset', at: 'bl', insetW: 440,
             main: { src: '06-livestock-inputs.jpg', crop: [1200, 160, 3920, 2520] },
             inset: { src: '06-livestock-inputs.jpg', crop: [64, 1580, 1104, 300] } } },
]);

Square.slides('square_industry_production_label', [
  { title: 'Production on the label', sub: 'Green while producing, dark while idle',
    media: { src: '07-pickup-mines.jpg', crop: [1280, 192, 1040, 900] } },
  { title: 'Matches the window', sub: 'The same number the industry window shows',
    media: { layout: 'inset', at: 'tr', insetW: 560,
             main: { src: '03-fishing-label.jpg', crop: [1760, 640, 1440, 1160] },
             inset: { src: '04-fishing-window.jpg', crop: [3848, 280, 1184, 340] } } },
  { title: 'Production vs. pickup', sub: 'See at a glance if your lines keep up',
    media: { layout: 'inset', at: 'br', insetW: 460,
             main: { src: '07-pickup-mines.jpg', crop: [1990, 1520, 640, 500] },
             inset: { src: '07-pickup-mines.jpg', crop: [1560, 420, 560, 300] } } },
  { title: 'A pair per output', sub: 'Both pills can be turned off in settings',
    media: { layout: 'inset', at: 'bl', insetW: 460,
             main: { src: '08-pickup-plants.jpg', crop: [2774, 1200, 720, 520] },
             inset: { src: '08-pickup-plants.jpg', crop: [1120, 780, 520, 260] } } },
  { title: 'Warehouse in and out', sub: 'Cargo per year, matching the warehouse window',
    media: { layout: 'inset', at: 'bl', insetW: 460,
             main: { src: '09-warehouse.jpg', crop: [1792, 973, 1280, 973] },
             inset: { src: '09-warehouse.jpg', crop: [3871, 435, 1134, 568] } } },
]);

Square.slides('square_no_factory_passengers', [
  { title: 'No passengers at factories', sub: 'New lines skip passenger loading at industry stops',
    media: { layout: 'stack', labels: ['Game default', 'With the mod'],
             items: [{ src: '01-before.jpg', crop: [224, 1730, 1328, 320] },
                     { src: '02-after.jpg', crop: [224, 1730, 1328, 320] }] } },
]);

Square.slides('square_problem_radar', [
  // Captures 2026-10-10 (rev 6). Radar window x 1076-4050, y 684-2052; fleet window x 2064-4080, y 672-2064.
  // Rev 10 (2026-10-14): 11/13/16/17 are those captures with the redesigned window pasted over the old one at the
  // same place and scale (user screenshots of the new UI, pasted by plans/square_problem_radar/shots/overlay_rev10.py). The new fleet
  // window is shorter: x 2066-4079, y 674-1788.
  { title: 'Every problem, one list', sub: 'Vehicles, lines, stations, fleet and money',
    media: { src: '11-all-tab.jpg', crop: [1064, 676, 3000, 1392] } },
  { title: 'Old and worn vehicles', sub: 'Upg opens the fleet of that vehicle\'s line',
    media: { src: '02-fleet-tab-upg.jpg', crop: [1064, 676, 3000, 1392] } },
  { title: 'Upgrade a tired fleet', sub: 'Line stats, last year\'s money, every model',
    media: { src: '13-fleet-window.jpg', crop: [2066, 662, 2030, 1140] } },
  { title: 'Pick the new model', sub: 'In the game\'s own Replace Vehicles window',
    media: { src: '04-replace-vehicles.jpg', crop: [1580, 196, 2996, 1784] } },
  { title: 'Lines losing money', sub: 'A year of losses, ranked by severity',
    media: { src: '05-economy-tooltip.jpg', crop: [1064, 676, 3204, 1392] } },
  { title: 'Snooze what you accept', sub: 'Zz hides an alert for a month up to 5 years',
    media: { src: '16-snoozed.jpg', crop: [1064, 676, 3000, 1392] } },
  { title: 'Off, List or Notify', sub: 'Choose how each alert reaches you',
    media: { src: '17-settings.jpg', crop: [1064, 676, 3000, 1392] } },
]);

Square.slides('square_better_minimap', [
  // Captures 2026-10-10 11:00 (rev 5, sub-arctic save), same camera for 21-27. The minimap window is
  // x 4110-5090, y 165-2255 (its map 4116-5079 x 268-2190); the filter window x 3255-4100, y 165-1080.
  { title: 'Roads, rails and towns', sub: 'Tick Net to draw your network on the map',
    media: { layout: 'wipe', labels: ['Off', 'Net'], split: 0.5,
             before: '27-plain.jpg', after: '26-net.jpg', crop: [4116, 640, 963, 1060] } },
  { title: 'High visibility', sub: 'Tick Viz for colours that stand out anywhere',
    media: { layout: 'wipe', labels: ['Net', 'Viz'], split: 0.5,
             before: '26-net.jpg', after: '23-ind-viz.jpg', crop: [4116, 640, 963, 1060] } },
  { title: 'Find any industry', sub: 'Search by name or cargo, tick the types you want',
    media: { src: '21-filter-search.jpg', crop: [3245, 160, 1855, 1560] } },
  { title: 'Shift+click to spotlight', sub: 'Hold Shift and click a resource to spotlight it',
    media: { src: '24-hover-cement.jpg', crop: [4110, 430, 990, 1250] } },
  { title: 'Your map at a glance', sub: 'Small or large; the box follows the camera',
    // Inset at about the main crop's scale, so S reads smaller than L.
    media: { layout: 'inset', at: 'bl', insetW: 230,
             main: { src: '28-mountain-large.jpg', crop: [2150, 150, 2950, 2150] },
             inset: { src: '29-mountain-small.jpg', crop: [4595, 165, 495, 1125] } } },
  { title: 'In the map editor too', sub: 'Redraws after every Generate',
    // 32-map-editor.jpg (rev 7, 2026-10-10 16:11): minimap x 4518-5056, y 166-909; the Generate
    // Heightmap panel's preview x 3000-4115, y 1515-2630 shows the same terrain.
    // The zoomed minimap sits over the small original (top right); the crop stops above the toolbar.
    media: { layout: 'inset', at: 'tr', insetW: 360,
             main: { src: '32-map-editor.jpg', crop: [2150, 130, 2970, 2510] },
             inset: { src: '32-map-editor.jpg', crop: [4515, 165, 545, 745] } } },
  { title: 'Text or icon', sub: 'Pick the top bar button style in the mod settings',
    // Top-left corner, same 5K scale: 30-icon-button.jpg is a 1288x308 piece from the screen's top-left.
    media: { layout: 'stack', labels: ['Text', 'Icon'],
             items: [{ src: '27-plain.jpg', crop: [0, 0, 450, 210] },
                     { src: '30-icon-button.jpg', srcW: 1288, crop: [0, 0, 450, 210] }] } },
]);

Square.slides('square_one_way_roads', [
  { title: 'One-way from 1900', sub: 'Cobblestone streets and gravel country roads',
    media: { layout: 'inset', at: 'br', insetW: 620,
             main: { src: '01-grid.jpg', crop: [950, 200, 3530, 1970] },
             inset: { src: '01-grid.jpg', crop: [1024, 2400, 3072, 230] } } },
  { title: 'Traffic follows the arrows', sub: 'Every lane runs the way you drag',
    media: { src: '02-closeup.jpg', crop: [950, 200, 3500, 1950] } },
  { title: 'Next to the two-way', sub: 'Same menu, same unlock year, arrow on the icon',
    media: { src: '03-tooltip.jpg', crop: [1230, 1330, 2710, 1306] } },
]);

Square.slides('square_bulk_bulldozer', [
  { title: 'Paint, then bulldoze', sub: 'Roads and buildings in one stroke, cost shown first',
    media: { layout: 'inset', at: 'bl', insetW: 440,
             main: { src: '01-town-selection.jpg', crop: [768, 333, 3072, 1715] },
             inset: { src: '01-town-selection.jpg', crop: [56, 1523, 883, 461] } } },
  { title: 'See it before it goes', sub: 'Selected roads turn red until you press Bulldoze',
    media: { src: '02-roundabout-selection.jpg', crop: [947, 512, 2509, 1613] } },
  { title: 'Brush from 5 to 200 m', sub: 'Hover to preview what a stroke will catch',
    media: { layout: 'inset', at: 'bl', insetW: 440,
             main: { src: '03-big-brush.jpg', crop: [960, 768, 1160, 1178] },
             inset: { src: '03-big-brush.jpg', crop: [56, 1536, 883, 435] } } },
  { title: 'Pick what goes', sub: 'Filters for roads, tracks, stations, assets and towns',
    media: { src: '01-town-selection.jpg', crop: [56, 1510, 876, 1105] } },
  { title: 'Find it under Tools', sub: 'Road or Rail menu, Tools tab, first entry',
    media: { layout: 'inset', at: 'tr', insetW: 460,
             main: { src: '06-menu-entry.jpg', crop: [986, 1500, 2598, 1300] },
             inset: { src: '06-menu-entry.jpg', crop: [1011, 2394, 371, 243] } } },
]);

Square.slides('square_roundabouts', [
  // Rev 6 gallery, captures 2026-10-10 (18-33 world shots, 40-44 settings panels; their empty map is
  // never shown). Settings panel crops: x 56-934; menu strip y 2406-2624. Order changed throughout:
  // `make modio ARGS=--apply` replaces the whole gallery. Kept to 10: the Hub failed with mod.io error 13003
  // FILE_TOO_MANY at 22 and at 19 slides (docs/findings.md). Now 9 at most (tools/render_shots.py MAX_SLIDES).
  { title: 'Rings, junctions, interchanges', sub: 'Seven entries in the Road menu',
    media: { layout: 'inset', at: 'bl', insetW: 1000,
             main: { src: '20-horizon-mix.jpg', crop: [0, 720, 5120, 2160] },
             inset: { src: '40-settings-roundabouts.jpg', crop: [1000, 2400, 3140, 230] } } },
  { title: 'Mix and match', sub: 'Ovals, chains, junctions and interchanges',
    media: { src: '19-oblique-mix.jpg', crop: [0, 0, 4640, 2520] } },
  { title: 'Better Roundabouts', sub: 'Round or oval, 3 to 6 arms, 1 to 4 lanes',
    media: { layout: 'inset', at: 'tr', insetW: 440,
             main: { src: '33-ovals-chains.jpg', crop: [0, 0, 5120, 2880] },
             inset: { src: '40-settings-roundabouts.jpg', crop: [56, 832, 878, 1792] } } },
  { title: 'Hamburger roundabouts', sub: 'A road straight through the ring, with splitter islands',
    media: { src: '15-oblique-hamburger.jpg', crop: [2000, 380, 2240, 1480] } },
  { title: 'Magic Roundabout', sub: 'Five mini roundabouts on a two-way ring',
    media: { layout: 'inset', at: 'tr', insetW: 440,
             main: { src: '30-magic-trees.jpg', crop: [800, 240, 3000, 2640] },
             inset: { src: '41-settings-magic.jpg', crop: [56, 1605, 878, 1019] } } },
  { title: 'Channelized junction', sub: 'Slip lanes and islands for a T or X junction',
    media: { layout: 'inset', at: 'tr', insetW: 440,
             main: { src: '14-top-down-variety.jpg', crop: [1668, 608, 1360, 880] },
             inset: { src: '42-settings-channel.jpg', crop: [56, 1183, 878, 1441] } } },
  { title: 'Dumbbell or two-bridge', sub: 'Two roundabouts, or one ring on two bridges',
    media: { src: '23-dumbbell-magic-chain.jpg', crop: [240, 320, 2680, 2560] } },
  { title: 'Parclo and Diamond', sub: 'Highway interchanges with one-way ramps',
    media: { layout: 'inset', at: 'tr', insetW: 440,
             main: { src: '25-parclo-diamond.jpg', crop: [400, 400, 4400, 2480] },
             inset: { src: '44-settings-parclo2.jpg', crop: [56, 1336, 878, 1288] } } },
  { title: 'Every layout and scale', sub: 'Next to the game\'s own interchanges',
    media: { layout: 'inset', at: 'bl', insetW: 1000,
             main: { src: '24-interchange-grid.jpg', crop: [0, 640, 4640, 1920] },
             inset: { src: '44-settings-parclo2.jpg', crop: [1000, 2400, 3140, 230] } } },
]);

Square.slides('square_line_revert', [
  { title: 'Undo for your lines', sub: 'Undo and Redo, right next to Auto-Rename',
    media: { layout: 'inset', at: 'tr', insetW: 600,
             main: { src: '04-buttons.jpg', crop: [1616, 440, 1984, 1680] },
             inset: { src: '04-buttons.jpg', crop: [208, 1624, 1360, 640] } } },
  { title: 'One edit per click', sub: 'The tooltip names what the next click undoes',
    media: { src: '01-undo-tooltip-many.jpg', crop: [208, 1616, 2064, 680] } },
  { title: 'Step back, then redo', sub: 'Redo puts it back; Shift+click reverts all',
    media: { src: '03-undo-stop-removed.jpg', crop: [208, 1616, 2160, 520] } },
]);

Square.slides('square_line_manager_plus', [
  // Captures 2026-10-11 (rev 1). Line Manager window x 208-1576, y 200-2600; other mods' buttons sit in the top
  // strip (y < 150) and top centre (x 1400-1660, y < 140): crops stay clear of both.
  { title: 'Every line, one hover away', sub: 'Hover a line on the map; Shift-click to manage it',
    media: { src: '01-map-hover-bus.jpg', crop: [2300, 880, 1960, 1260] } },
  // 16 (rev 5, 2026-10-11): 5120x2880, a furniture truck line's vehicle list with the adaptive columns: a long
  // vehicle name runs up to the load, the picture column only as wide as the pictures. Line Manager x 205-1575; from
  // the line list to the line's stops (y 640-2150), both ends faded. Replaces 15 (rev 4's fixed columns).
  { title: 'Loads at a glance, rebalanced columns', sub: 'See capacity directly from the line window and more space for vehicle names',
    media: { src: '16-vehicle-list-long-names.jpg', crop: [205, 640, 1370, 1510], fade: [0.14, 0.18] } },
  // 14 (rev 3 final, 2026-10-11): 5120x2880, a bus line's vehicle list, the third bus's picture hovered: the info
  // box right of the Line Manager (x 1600-2750, y 1230-1525). One wide strip rendered too small, so a stack: the
  // vehicle rows (hovered one last), then the box.
  { title: 'Hover any vehicle', sub: 'Its line, parts, speed, condition and costs at a glance',
    media: { layout: 'stack', gap: 28, labels: ['Hover its picture', 'Vehicle info'],
             items: [{ src: '14-vehicle-hover.jpg', crop: [205, 1080, 1360, 215] },
                     { src: '14-vehicle-hover.jpg', crop: [1595, 1222, 1165, 310] }] } },
  // 20/21 (rev 10, 2026-10-19): 5120x2880, the line panel's Buy Vehicles button and the store it opens, cargo filter
  // already set: a bus line (passenger toggle) and a furniture truck line (furniture toggle). The store's cargo
  // filter bar and the top of its vehicle list (x 1613-2944, y 512-1140).
  // Replaces the rev 3 "Trucks, planes, trains" slide (10-13) to stay within the 9-slide cap.
  { title: 'Buy the right vehicles', sub: "Buy Vehicles opens the store filtered to the line's cargo",
    media: { layout: 'stack', gap: 28, chips: 'after', labels: ['Bus line: passengers', 'Truck line: furniture'],
             items: [{ src: '20-buy-filter-bus.jpg', crop: [1613, 512, 1331, 628] },
                     { src: '21-buy-filter-cargo.jpg', crop: [1613, 512, 1331, 628] }] } },
  { title: 'Hover any line in the list', sub: 'Its fleet and stats, right beside the Line Manager',
    media: { src: '02-list-row-hover.jpg', crop: [200, 200, 2580, 750] } },
  // 03/04 merged (rev 6, 2026-10-18, gallery cap 9): the Send to Line list's estimate tooltip, then the same
  // estimate hovering the target line on the map (04: tooltip x 2580-3550, y 1296-1566; Line Manager left of x 1600).
  { title: 'Know where you send', sub: 'In the list or on the map: capacity, frequency and rate, before and after',
    media: { layout: 'stack', gap: 28, chips: 'after', labels: ['Hover a line in the list', 'Or the line on the map'],
             items: [{ src: '03-send-list-estimate.jpg', crop: [300, 1052, 2190, 830] },
                     { src: '04-send-map-estimate.jpg', crop: [1640, 1060, 2190, 600] }] } },
  // 05/06 merged (rev 6, 2026-10-18, gallery cap 9): the rate matcher window (06, cut below the current model's
  // table, before Compare models), then the line menu it opens from (05: a 1310x670 close-up of the Auto-Rename-style
  // menu, rev 10 2026-10-20: header card, Match line rate, Duplicate, Reverse, Duplicate + reverse). The stack aligns
  // on the first item's width, so the wider window goes first.
  // rev 12 (2026-10-20): collage so all three read larger: the rate matcher window on top, the menu with Set cargo
  // for all stops (22) and its cargo page (23, Back, Clear all, the cargos the stops can take) side by side below.
  // 22/23 are window captures (srcW).
  { title: 'Match, duplicate, reverse, set cargo', sub: 'Fleet sizing and whole-line edits from one line menu',
    media: { layout: 'collage', items: [
      { src: '06-rate-matcher.jpg', crop: [2156, 536, 2036, 850], x: 1345, y: 330, w: 1070 },
      { src: '22-line-actions-set-cargo.jpg', srcW: 1450, crop: [153, 1556, 1175, 645], x: 1065, y: 765, w: 520 },
      { src: '23-set-cargo-page.jpg', srcW: 1462, crop: [150, 1544, 1170, 578], x: 1615, y: 751, w: 520 }] } },
  // 07/08: same camera, 5 stops (Undo tooltip) and 3 stops after two Undos (Redo tooltip). Line editor panel
  // x 208-1576 from y 1620; the Undo tooltip runs to x 2140; stops 3 and 5 on the map at x 2730-2830, y 1580-1700.
  { title: 'Undo any stop edit', sub: 'Shift+click Undo reverts it all; Redo brings it back',
    media: { layout: 'stack', labels: ['Undo', 'Redo'],
             items: [{ src: '07-undo-tooltip.jpg', crop: [208, 1540, 2760, 680] },
                     { src: '08-redo-tooltip.jpg', crop: [208, 1540, 2760, 680] }] } },
  // 26/27 (rev 11, 2026-10-20): window captures (not 5120 wide, hence srcW) of the AP Passengers line; the bottom
  // stats row with the hover tooltip under it: Utilization (12 months / 2 / 5 years, "~" while filling) and Balance
  // (last year / 2 / 5 years). Replaces the rev 6 "Utilization, now and on average" slide (17-19) to stay within
  // the 9-slide cap.
  { title: 'Hover for the long view', sub: 'Utilization and balance over 12 months, 2 and 5 years',
    media: { layout: 'stack', gap: 28, chips: 'after', labels: ['Utilization', 'Balance'],
             items: [{ src: '27-utilization-tooltip.jpg', srcW: 1614, crop: [346, 2299, 1078, 346] },
                     { src: '26-balance-tooltip.jpg', srcW: 1844, crop: [586, 2310, 1070, 286] }] } },
]);

Square.slides('square_better_auto_vehicle_renamer', [
  // Captures 2026-10-20 (rev 1): window crops of the base Line Manager (not 5120 wide, hence srcW), default
  // settings. The vehicle list (checkbox column to the vehicle pictures) sits at y ~930-1210 in each; the
  // toolbar above it at y ~830-925. 01 buses, 02 ships (line CarWoo-FisLan-IC-1), 03 ships (Hay-FisLan-IC-1),
  // 04 aircraft.
  { title: 'Every vehicle numbered', sub: 'Fleet number, model and purchase year, in the base Line Manager',
    // Only the vehicle list (toolbar to the last row), large: the slide reads as vehicle names, not line names
    // (user 2026-10-20; an inset of the line list covered the names).
    media: { src: '01-buses.jpg', srcW: 1568, crop: [110, 828, 1345, 382] } },
  { title: 'One letter per type', sub: 'B buses, S ships, A aircraft; each type counts on its own',
    media: { layout: 'stack', gap: 28, chips: 'after', labels: ['Buses: B', 'Ships: S', 'Aircraft: A'],
             items: [{ src: '01-buses.jpg', srcW: 1568, crop: [128, 930, 1152, 278] },
                     { src: '02-ships-ic.jpg', srcW: 1556, crop: [62, 915, 1152, 345] },
                     { src: '04-aircraft.jpg', srcW: 1628, crop: [150, 963, 1152, 278] }] } },
  { title: 'One count across all lines', sub: 'Ships on two lines share one S series; sold numbers are never reused',
    media: { layout: 'stack', gap: 28, chips: 'after', labels: ['Ship line CarWoo-FisLan-IC-1', 'Ship line Hay-FisLan-IC-1'],
             items: [{ src: '02-ships-ic.jpg', srcW: 1556, crop: [62, 915, 1152, 345] },
                     { src: '03-ships-hay.jpg', srcW: 1572, crop: [135, 953, 1152, 276] }] } },
  // Examples rendered by the mod's own Text.render / modelName / lineName (2026-10-20); update them when the
  // naming code changes.
  { title: 'Name it your way', sub: 'Format, prefix, separators, digits, counting, year and more in the mod settings',
    media: { layout: 'table', col1: 36, head: ['Setting', 'Name'], rows: [
      ['Default', 'B-0067 | Postbus ET 13 (1916)'],
      ['Model + number', 'Postbus ET 13 | B-0067 (1916)'],
      ['Line + number', 'Bus 12 | B-0067 (1916)'],
      ['Counting per line', 'Bus 12 #03 | Postbus ET 13 (1916)'],
      ['Short prefix, dot', 'Shp-0032 · Sternwheeler (1916)'],
      ['Year first', '1918-0040 | Dunara Castle'],
      ['3 digits, short model', 'B-205 | Deck Seat Car (1934)'],
      ['Train length', 'L-0045 | 2-6-0 Mogul +4 (1911)'],
      ['Mark past its lifespan', 'B-0067 | Postbus ET 13 (1916) *'],
    ] } },
]);

Square.slides('square_names_us_washington', [
  { title: 'Real city streets', sub: 'Seattle stops get Pike, Pine & Union Street',
    media: { layout: 'inset', at: 'bl', insetW: 760,
             main: { src: '01-seattle-line.jpg', crop: [2080, 860, 1440, 1260] },
             inset: { src: '01-seattle-line.jpg', crop: [225, 1740, 1310, 360] } } },
  { title: 'Every city its own', sub: 'Bellevue Way, NE 4th Street, 108th Avenue NE',
    media: { layout: 'inset', at: 'bl', insetW: 760,
             main: { src: '02-bellevue-line.jpg', crop: [1880, 930, 1440, 1060] },
             inset: { src: '02-bellevue-line.jpg', crop: [225, 1740, 1310, 425] } } },
  { title: 'Real airports too', sub: 'Stations, airports and harbours get real names',
    media: { src: '03-seatac-airport.jpg', crop: [1260, 900, 2000, 1200] } },
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '520 towns, picked by map climate'],
      ['Local-style street names', '132'],
      ['Real streets for new Road Stops', '374 streets in 24 cities'],
      ['Real names for new stations, airports and ferry terminals', '52 names in 18 cities'],
      ['Neighbourhood names for bus and tram stations', '118 in 13 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_alaska', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '282 towns, picked by map climate'],
      ['Local-style street names', '128'],
      ['Real streets for new Road Stops', '250 streets in 9 cities'],
      ['Real names for new train stations, airports and ferry terminals', '48 names in 32 cities'],
      ['Neighbourhood names for bus and tram stations', '28 in 1 city'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_arizona', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '275 towns, picked by map climate'],
      ['Local-style street names', '129'],
      ['Real streets for new Road Stops', '316 streets in 13 cities'],
      ['Real names for new train stations and airports', '17 names in 14 cities'],
      ['Neighbourhood names for bus and tram stations', '38 in 3 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_california', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '550 towns, picked by map climate'],
      ['Local-style street names', '127'],
      ['Real streets for new Road Stops', '360 streets in 13 cities'],
      ['Real names for new train stations, airports and ports', '105 names in 17 cities'],
      ['Neighbourhood names for bus and tram stations', '92 in 4 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_colorado', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '334 towns, picked by map climate'],
      ['Local-style street names', '125'],
      ['Real streets for new Road Stops', '293 streets in 12 cities'],
      ['Real names for new train stations and airports', '25 names in 10 cities'],
      ['Neighbourhood names for bus and tram stations', '42 in 2 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_florida', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '479 towns, picked by map climate'],
      ['Local-style street names', '137'],
      ['Real streets for new Road Stops', '336 streets in 13 cities'],
      ['Real names for new train stations, airports and ports', '34 names in 16 cities'],
      ['Neighbourhood names for bus and tram stations', '63 in 4 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_hawaii', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '131 towns, picked by map climate'],
      ['Local-style street names', '123'],
      ['Real streets for new Road Stops', '299 streets in 13 cities'],
      ['Real names for new train stations, airports and harbours', '29 names in 20 cities'],
      ['Neighbourhood names for bus and tram stations', '51 in 2 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_minnesota', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '485 towns, picked by map climate'],
      ['Local-style street names', '129'],
      ['Real streets for new Road Stops', '329 streets in 12 cities'],
      ['Real names for new train stations and airports', '49 names in 38 cities'],
      ['Neighbourhood names for bus and tram stations', '96 in 3 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_new_mexico', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '278 towns, picked by map climate'],
      ['Local-style street names', '128'],
      ['Real streets for new Road Stops', '401 streets in 12 cities'],
      ['Real names for new train stations and airports', '35 names in 28 cities'],
      ['Neighbourhood names for bus and tram stations', '50 in 2 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_new_york', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '541 towns, picked by map climate'],
      ['Local-style street names', '129'],
      ['Real streets for new Road Stops', '381 streets in 13 cities'],
      ['Real names for new train stations, airports and harbours', '102 names in 48 cities'],
      ['Neighbourhood names for bus and tram stations', '177 in 5 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_oregon', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '357 towns, picked by map climate'],
      ['Local-style street names', '162'],
      ['Real streets for new Road Stops', '342 streets in 12 cities'],
      ['Real names for new train stations and airports', '81 names in 44 cities'],
      ['Neighbourhood names for bus and tram stations', '95 in 4 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_pennsylvania', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '488 towns, picked by map climate'],
      ['Local-style street names', '137'],
      ['Real streets for new Road Stops', '372 streets in 13 cities'],
      ['Real names for new train stations, airports and ferry landings', '109 names in 54 cities'],
      ['Neighbourhood names for bus and tram stations', '109 in 2 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_names_us_texas', [
  // Counts match the rev 4 description (tools/gen_state_mod.py); update both when the data changes.
  { title: 'More than a name list', sub: 'It names the stops and stations you build',
    media: { layout: 'table', head: ['Feature', 'This mod'], rows: [
      ['Town name set', '533 towns, picked by map climate'],
      ['Local-style street names', '128'],
      ['Real streets for new Road Stops', '367 streets in 13 cities'],
      ['Real names for new train stations, airports and ports', '91 names in 25 cities'],
      ['Neighbourhood names for bus and tram stations', '88 in 4 cities'],
      ['Real names in renamed towns, with any name set', 'Yes'],
      ['Settings', 'Street and station toggles'],
    ] } },
]);

Square.slides('square_smart_lanes', [
  // Rev 8 (2026-10-16): three slides in front for the rev 8 features (Smart lights, automatic light timing, Record
  // traffic), then six earlier ones. Dropped for them: "From one ring to a city" (a second test-map collage),
  // "Works with traffic lights" (lanes fitted to the game's phases: superseded by Smart lights; its crossroads is the
  // timing slide's scene) and "Built for rush hour" (its busy road is the Record traffic slide's scene).
  // 19-23 are in-game panel captures at 2x (srcW = their width); the game's Account / Vice President HUD below each
  // panel is cropped off. 20-panel-game-default.jpg shows the old badge "Game default (kept)": only its Smart lanes
  // button is used. Numbers: RESULTS.md "Verdicts" ("Light plans: axis (rev 8) vs game default": +23 % / +26 %
  // cars/min on lit 2x2 / 3x3 crossroads, 6 of 6 sets) and the earlier ones as before.
  // Rev 8 (user 2026-10-16): the first slide shows both offerings at once: smart lanes (the junction hover) and
  // Smart lights (the Crossing window with the 4-phase plan, the tool's info with both checks), one number each
  // (+16 cars a minute: RESULTS.md, as "Roundabouts keep moving"; +23-26 %: the light plans A/B).
  { title: '<span style="font-size:72px;line-height:80px;white-space:nowrap">Smart lanes +<br>Smart lights</span>', sub: 'Lanes that fit every junction, light phases that fit the lanes',
    media: { layout: 'collage', items: [
      { src: '03-junction-hover.jpg', crop: [1000, 400, 2760, 1760], x: 1080, y: 330, w: 560, rot: -2, label: 'Smart lanes' },
      { src: '21-crossing-smart-phases.jpg', srcW: 1308, crop: [54, 14, 1200, 935], x: 1630, y: 290, w: 480, rot: 2 },
      { src: '22-panel-smart-lights.jpg', srcW: 944, crop: [56, 690, 830, 300], x: 1600, y: 820, w: 560, rot: 1 }],
      // the Crossing window's own title stays readable: its caption is a badge under it, not a corner chip
      badges: [{ big: 'Smart lights', small: 'Improved 4-phase plan: one green per road', x: 1390, y: 490 },
               { big: '+16 cars/min', small: 'through two-lane roundabouts', x: 840, y: 660 },
               { big: '+23-26 %', small: 'cars a minute at lit crossroads', x: 840, y: 820 }] } },
  { title: 'Lights that keep up', sub: 'Keep timing adjusted gives more green where cars keep waiting',
    media: { layout: 'collage', items: [
      { src: '07-crossing-phases.jpg', crop: [1100, 300, 2700, 2100], x: 1460, y: 400, w: 780 },
      { src: '19-settings-panel.jpg', srcW: 972, crop: [56, 40, 878, 1195], x: 1010, y: 560, w: 420, rot: -2, },
      { src: '22-panel-smart-lights.jpg', srcW: 944, crop: [56, 382, 822, 96], x: 1500, y: 870, w: 620, rot: 1 }] } },
  { title: 'Record traffic anywhere', sub: 'Vehicles per minute at any junction or roundabout, up to 20 at once',
    media: { layout: 'collage', items: [
      { src: '04-busy-road.jpg', crop: [0, 40, 5000, 2800], x: 1330, y: 330, w: 1000 },
      { src: '22-panel-smart-lights.jpg', srcW: 944, crop: [56, 545, 830, 380], x: 1070, y: 790, w: 500, rot: -2, label: 'Recording', dark: true },
      { src: '23-panel-recorded.jpg', srcW: 970, crop: [48, 560, 882, 490], x: 1600, y: 800, w: 500, rot: 2, label: 'Recorded' }] } },
  { title: 'Extensively tested', sub: 'Whole maps of twin towns: Smart Lanes against the game\'s lanes',
    media: { layout: 'collage', items: [
      { src: '10-bench-map.jpg', crop: [0, 0, 4640, 2520], x: 1330, y: 400, w: 1040 },
      { src: '08-bench-group.jpg', crop: [1200, 60, 2800, 2500], x: 1000, y: 790, w: 360, rot: -3, label: 'Test group' },
      { src: '09-roundabout-top.jpg', crop: [1200, 120, 2800, 2500], x: 1340, y: 820, w: 360, rot: 2, label: 'Roundabout' },
      { src: '07-crossing-phases.jpg', crop: [1600, 720, 1920, 1714], x: 1680, y: 790, w: 360, rot: -2, label: 'Lit crossroads' }] } },
  // Rev 5 (2026-10-14): the 2-lane town roundabout default (sl_rmid). Smart Lanes adds a node half way between the arms
  // and does every lane change there (orange); the arm junctions (teal) only take exits and entries. 18-ring-mid-nodes.jpg
  // is a 2928 px wide capture (srcW). Numbers: RESULTS.md, bench s4 v5 (mid-only on the mid-node ring vs the game on a
  // plain ring, one pair).
  { title: 'Smarter small roundabouts', sub: 'Cars change lanes at a new node between the arms, never at the exits',
    media: { src: '18-ring-mid-nodes.jpg', srcW: 2928, crop: [330, 100, 2260, 1900],
             badges: [{ big: '+47 %', small: 'more cars through', x: 1500, y: 740, w: 330 },
                      { big: '12.4 km/h', small: 'vs 8.0 with game lanes', x: 1500, y: 875, w: 330 }] } },
  { title: 'Roundabouts keep moving', sub: '+16 cars a minute through two-lane roundabouts in tests',
    media: { src: '09-roundabout-top.jpg', crop: [1040, 0, 3080, 2640] } },
  { title: 'Works on its own', sub: 'On by default: build a junction and it gets smart lanes',
    media: { src: '06-roundabout-queue.jpg', crop: [380, 330, 4230, 2000] } },
  // Inset: the rev 8 tool's Smart lanes button (20-panel-game-default.jpg, top row only; a multi selection shows the
  // lane row alone).
  { title: 'A whole district at once', sub: 'Shift+click junctions and roads, then Smart lanes for them all',
    media: { layout: 'inset', at: 'bl', insetW: 460,
             main: { src: '16-district-select.jpg', crop: [980, 80, 3400, 2020] },
             inset: { src: '20-panel-game-default.jpg', srcW: 966, crop: [74, 60, 822, 96] } } },
  { title: 'Lanes that never cross', sub: 'Each entry lane gets its own ring lane and exit',
    media: { src: '03-junction-hover.jpg', crop: [1000, 400, 2760, 1760] } },
]);

Square.slides('square_supply_gaps', [
  { title: 'See what your routes miss', sub: 'Every town building that needs a cargo it isn\'t getting',
    media: { layout: 'inset', at: 'bl', insetW: 380,
             main: { src: '01-all-needed-labels.jpg', crop: [1080, 0, 2920, 2620] },
             inset: { src: '01-all-needed-labels.jpg', crop: [56, 720, 900, 1130] } } },
  { title: 'Not reached or running dry', sub: 'Arrow: no stop in range. Exclamation: stock empty',
    media: { layout: 'inset', at: 'bl', insetW: 380,
             main: { src: '03-fish-in-range-empty.jpg', crop: [1640, 240, 2640, 2160] },
             inset: { src: '03-fish-in-range-empty.jpg', crop: [56, 720, 900, 1130] } } },
  { title: 'Every district in numbers', sub: 'The share of buildings each cargo reaches',
    media: { src: '01-all-needed-labels.jpg', crop: [1640, 700, 1240, 840] } },
  { title: 'One cargo at a time', sub: 'Counts per cargo for the towns on screen',
    media: { layout: 'inset', at: 'tl', insetW: 900, insetY: 0.36,
             main: { src: '04-fuel-tooltip.jpg', crop: [1950, 340, 1790, 1720] },
             inset: { src: '04-fuel-tooltip.jpg', crop: [56, 968, 1880, 384] } } },
  { title: 'Stays on while you build', sub: 'Gaps: on keeps the markers up as you place road stops',
    media: { layout: 'inset', at: 'tl', insetW: 300,
             main: { src: '07-gaps-on-ridge.jpg', crop: [990, 100, 2460, 1900] },
             inset: { src: '07-gaps-on-ridge.jpg', crop: [690, 20, 210, 90] } } },
]);

Square.slides('square_better_bus_overlay', [
  { title: 'See your lines', sub: 'Every line route stays on the map while you place a stop',
    media: { layout: 'wipe', labels: ['Before', 'After'], darkChips: true, split: 0.42,
             before: '07-lines-off.jpg', after: '06-lines-on.jpg',
             crop: [307, 102, 3328, 1946], beforeCrop: [317, 325, 2862, 1674] } },
  // Captures 2026-10-10 (rev 5 toggles). Toggles panel: x 56-934, y 2140-2640 (stop tool), y 2330-2640 (bus lane tool).
  { title: 'Spot your bus lanes', sub: 'Switch the line routes off to see which roads are done',
    media: { layout: 'wipe', labels: ['Off', 'On'], darkChips: true, split: 0.45,
             before: '11-buslane-lines-off.jpg', after: '12-buslane-lines-on.jpg',
             crop: [400, 60, 3500, 2050] } },
  { title: 'Pick what you see', sub: 'Line routes, building colors and stop tags each switch off',
    media: { layout: 'inset', at: 'bl', insetW: 560,
             main: { src: '13-stop-all-on.jpg', crop: [256, 60, 3500, 2050] },
             inset: { src: '13-stop-all-on.jpg', crop: [56, 2140, 878, 462] } } },
  { title: 'Find the gaps', sub: 'Unserved buildings stand out; stops show who is waiting',
    media: { layout: 'inset', at: 'bl', insetW: 520,
             main: { src: '02-placing-waiting.jpg', crop: [1024, 160, 3328, 2000] },
             inset: { src: '02-placing-waiting.jpg', crop: [2212, 873, 856, 570] } } },
  { title: 'Spot unconnected stops', sub: 'A "No line" tag marks every stop no line serves yet',
    media: { layout: 'inset', at: 'tr', insetW: 420,
             main: { src: '08-no-line-placing.jpg', crop: [1024, 154, 3072, 1997] },
             inset: { src: '08-no-line-placing.jpg', crop: [1830, 870, 330, 165] } } },
  { title: 'Connect new stops fast', sub: 'While you build a line, the tags show where it should go next',
    media: { layout: 'inset', at: 'br', insetW: 520,
             main: { src: '10-no-line-editing.jpg', crop: [1613, 461, 1971, 1843] },
             inset: { src: '10-no-line-editing.jpg', crop: [225, 1741, 1331, 307] } } },
  { title: 'Busy stops at a glance', sub: 'Pins go from blue to red as passengers pile up',
    media: { layout: 'inset', at: 'tr', insetW: 600,
             main: { src: '03-lines-overview.jpg', crop: [1587, 60, 3440, 2500] },
             inset: { src: '03-lines-overview.jpg', crop: [1941, 743, 1071, 550] } } },
  { title: 'Red means crowded', sub: 'The same colours while you edit a line',
    media: { src: '05-busy-closeup.jpg', crop: [1792, 230, 2560, 1920] } },
]);

Square.slides('square_blank_slate', [
  { title: 'Pick Blank Slate', sub: 'In the generator list for every climate',
    media: { layout: 'inset', at: 'bl', insetW: 940,
             main: { src: '01-new-game.jpg', crop: [3540, 560, 1200, 1200] },
             inset: { src: '01-new-game.jpg', crop: [384, 650, 2535, 300] } } },
  { title: 'Flat as a pancake', sub: 'One level island: no hills, trees or rocks',
    media: { src: '02-island-top-down.jpg', crop: [180, 50, 4900, 2560] } },
  { title: 'Sea on every side', sub: 'A short beach down to deep water, all the way round',
    media: { src: '03-coast.jpg', crop: [770, 385, 3840, 2175] } },
  { title: 'Build anywhere', sub: 'Every tile sits at 5 m, right up to the beach',
    media: { src: '04-town-on-coast.jpg', crop: [970, 460, 3120, 2100] } },
]);

Square.slides('square_passenger_destinations', [
  // Captures 2026-10-10 (rev 5). The entity window is x 3850-5030; the HUD bar starts at y 2660; other mods'
  // buttons sit in the top strip (y < 150, x < 1660): crops stay clear of both.
  { title: 'Where they\'re going', sub: 'Arrows from the stop to every destination',
    media: { layout: 'inset', at: 'br', insetW: 560,
             main: { src: '01-station-hialeah.jpg', crop: [26, 154, 3600, 2490] },
             inset: { src: '01-station-hialeah.jpg', crop: [3878, 174, 1119, 256] } } },
  { title: 'Two jumps', sub: 'Strong to their stop, faded on to their door',
    media: { layout: 'inset', at: 'tr', insetW: 560,
             main: { src: '02-bus-two-jumps.jpg', crop: [973, 640, 2816, 1971] },
             inset: { src: '02-bus-two-jumps.jpg', crop: [3878, 1318, 1119, 256] } } },
  { title: 'Hold Shift on the map', sub: 'Point at any stop or vehicle, get instant destination arrows',
    media: { src: '09-shift-hover.jpg', crop: [990, 589, 2700, 1888] } },
  { title: 'Hover a passenger', sub: 'Point at a Locate pin: their whole trip',
    media: { src: '06-hover-spencer.jpg', crop: [1946, 742, 3072, 1920] } },
  { title: 'Any passenger list', sub: 'On board, waiting or at home',
    media: { layout: 'inset', at: 'br', insetW: 500,
             main: { src: '04-hover-andrea.jpg', crop: [973, 640, 2816, 1971] },
             inset: { src: '04-hover-andrea.jpg', crop: [3886, 1242, 1119, 512] } } },
  { title: 'Ports and ferries too', sub: 'Every stop with waiting passengers',
    media: { layout: 'inset', at: 'br', insetW: 560,
             main: { src: '07-port-hialeah.jpg', crop: [205, 154, 3482, 2432] },
             inset: { src: '07-port-hialeah.jpg', crop: [3878, 174, 1119, 328] } } },
  { title: 'The whole crowd', sub: 'Up to 10 stops and 30 areas per window',
    media: { layout: 'inset', at: 'br', insetW: 560,
             main: { src: '08-port-rockledge.jpg', crop: [1664, 0, 2176, 1525] },
             inset: { src: '08-port-rockledge.jpg', crop: [3878, 174, 1119, 328] } } },
]);

Square.slides('square_stress_test', [
  // Captures 2026-10-10. The window is x 1741-3379, y 481-2394; HUD below y 2630, Debug button top left.
  { title: 'A city under load', sub: 'Turn a free game into a dense benchmark map',
    media: { src: '01-dense-city.jpg', crop: [998, 102, 2663, 2378] } },
  { title: 'Grow and spawn towns', sub: 'Up to x100, with ten build-out passes',
    media: { src: '02-towns-tab.jpg', crop: [1560, 400, 2000, 2120] } },
  { title: 'Fill the roads', sub: 'Vehicles, auto bus lines and a traffic clear',
    media: { src: '04-traffic-tab.jpg', crop: [1560, 400, 2000, 2120] } },
  { title: 'Money, year and speed', sub: 'Town ratings and notifications too',
    media: { src: '03-game-tab.jpg', crop: [1560, 400, 2000, 2120] } },
  { title: 'Towers in every block', sub: 'Benchmark mods on the busiest map you can',
    media: { src: '06-closeup.jpg', crop: [973, 154, 2611, 2304] } },
]);

Square.slides('square_organic_towns', [
  // 01, 10-15: Retina captures 2026-10-12..14 (5120x2880; 11-forest-edge is a 2336-wide crop with drawn arrows,
  // 12 the Blank Slate test map). 20-*-vanilla / 20-*-mod: the game's 2560x1440 tour shots of one town (entity id
  // in the name) on the same temperate seed after the same 40 simulated years (OT Dev Simulate + Tour): vanilla from
  // session 2026-10-14_0640_sqrl-sqsg load 2, the mod from 2026-10-16_1846_sqot load 2. 30-extra-*: that run's Works
  // and district towns (127368 Wheatden Timber Yard, 140715 Brantmerehall, 176691 New Seven Oaks). Names in the table: its NAME lines.
  { title: 'Towns that fit the land', sub: 'Streets wind along hills, rivers and shores',
    media: { src: '01-valley-town.jpg', crop: [400, 600, 3600, 2200] } },
  { title: 'Organic, not a grid', sub: 'One town, same seed, after 40 years',
    media: { layout: 'wipe', labels: ['Vanilla', 'Organic Towns'], srcW: 2560, split: 0.42,
             before: '20-60262-vanilla.jpg', after: '20-60262-mod.jpg', crop: [700, 300, 1150, 950] } },
  // 30-extra-127368: Wheatden (left), its Timber Yard Works (middle) and the saw mill by the lake (right).
  { title: 'Industry shapes the town', sub: 'Towns keep clear of the works and grow with your deliveries',
    media: { src: '30-extra-127368.jpg', srcW: 2560, crop: [100, 180, 2100, 1180],
      badges: [{ big: 'Room to grow', small: 'No streets where farms,\nmines and mills expand', x: 860, y: 870, w: 330 },
               { big: 'Deliveries', small: 'Industrial cargo makes a mill\ntown, passengers a home town', x: 1220, y: 870, w: 380 }] } },
  { title: 'Satellite towns', sub: 'Grown towns found districts and Works of their own',
    media: { layout: 'collage', items: [
      { src: '10-tickhill.jpg', crop: [480, 240, 3680, 2080], x: 1330, y: 320, w: 940, rot: -1.5, label: 'Tickhill-on-Sea, a shore district' },
      { src: '30-extra-176691.jpg', srcW: 2560, crop: [600, 0, 1500, 1000], x: 1120, y: 800, w: 600, rot: 2, label: 'New Seven Oaks, a district' },
      { src: '30-extra-140715.jpg', srcW: 2560, crop: [569, 0, 853, 910], x: 1650, y: 780, w: 400, rot: -2, label: 'Brantmerehall, a district' }] } },
  // Stop names from the STOPNAME lines of session 2026-10-16_1846_sqot (Two Waters, 60256) and 2026-10-14 runs
  // (Livestock Farm Gate, North Harbor Blvd).
  { title: 'Fitting street names', sub: 'Every new stop named after its own spot, never twice',
    media: { layout: 'collage', items: [
      { src: '20-60256-mod.jpg', srcW: 2560, crop: [560, 300, 1500, 600], x: 1340, y: 240, w: 960, rot: 0, label: 'Two Waters' }],
      table: { top: 470, head: ['A stop by', 'gets the name'], rows: [
        ['the river bridge', 'Arun Bridge'],
        ['the far end of the bridge', 'Bridge End'],
        ['the hilltop', 'Beacon Hill'],
        ['the road to the next town', 'Brynhaven Lane'],
        ['a livestock farm', 'Livestock Farm Gate']] } } },
  { title: 'Around the forest', sub: 'Towns grow into open fields and keep the woods',
    media: { src: '11-forest-edge.jpg', srcW: 2336, crop: [250, 100, 1850, 2000] } },
  { title: 'Every town its own form', sub: 'Long, radiating, clustered or along the shore',
    media: { layout: 'collage', items: [
      { src: '20-60261-mod.jpg', srcW: 2560, crop: [1000, 100, 700, 1300], x: 1040, y: 540, w: 420, rot: -2, label: 'Long' },
      { src: '20-60263-mod.jpg', srcW: 2560, crop: [950, 250, 1050, 900], x: 1560, y: 290, w: 520, rot: 2, label: 'Island town' },
      { src: '20-60266-mod.jpg', srcW: 2560, crop: [850, 450, 750, 800], x: 1450, y: 790, w: 360, rot: -1, label: 'Radiating' },
      { src: '20-60267-mod.jpg', srcW: 2560, crop: [850, 400, 850, 750], x: 1745, y: 760, w: 300, rot: 3, label: 'Clustered' }] } },
  { title: 'Names from the landscape', sub: 'Every town named after its own site',
    media: { layout: 'table', head: ['Town', 'Named for'], rows: [
      ['Two Waters', 'a bend where the river doubles back'],
      ['Watersmeet', 'two rivers meeting'],
      ['Hornholt Isle', 'a wooded spit in a lake'],
      ['Merehythe-on-Redwater', 'a landing on Redwater lake'],
      ['Dovemouth-in-the-Forest', 'the mouth of the Dove, in the woods'],
      ['Seachurch Cove', 'a church by a sheltered cove']] } },
  // 40-var-*: tour shots from the compare pages (plans/square_organic_towns/compare/): tropical (Asian list), dry,
  // US names (92 years and 1960), 203 years, a 1950 start and two more seeds. Numbers: every "SIMGROW stop" line in
  // .cache/logs (2026-10-16): 66 runs, 814 towns (sum of towns=), 40 to 203 simulated years.
  { title: 'Tested town by town', sub: 'Many seeds, climates, eras and name lists',
    media: { layout: 'collage', print: true, items: [
      { src: '40-var-01.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 953, y: 195, w: 285, rot: -2.5, label: 'Tropical' },
      { src: '40-var-02.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 1197, y: 210, w: 285, rot: 1.5, label: 'Dry' },
      { src: '40-var-03.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 1473, y: 190, w: 285, rot: -1 },
      { src: '40-var-04.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 1717, y: 205, w: 285, rot: 2.5, label: '203 years' },
      { src: '40-var-05.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 953, y: 425, w: 285, rot: 2 },
      { src: '40-var-06.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 1197, y: 410, w: 285, rot: -1.5, label: 'US names' },
      { src: '40-var-07.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 1473, y: 430, w: 285, rot: 1, label: 'From 1950' },
      { src: '40-var-08.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 1717, y: 415, w: 285, rot: -2 },
      { src: '40-var-09.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 953, y: 650, w: 285, rot: -1 },
      { src: '40-var-10.jpg', srcW: 1600, crop: [320, 135, 960, 630], x: 1197, y: 640, w: 285, rot: 2 },
      { src: '40-var-11.jpg', srcW: 1400, crop: [280, 118, 840, 551], x: 1473, y: 655, w: 285, rot: -2.5 },
      { src: '12-flat-town.jpg', crop: [700, 300, 3550, 2100], x: 1717, y: 645, w: 285, rot: 1.5, label: 'Blank Slate' }],
      badges: [{ big: '66', small: 'simulated test runs', x: 830, y: 800, w: 300 },
               { big: '814', small: 'towns grown and compared', x: 1180, y: 800, w: 320 },
               { big: '40-203', small: 'years per run', x: 1550, y: 800, w: 290 }] } },
]);

// Photo Mode: its own postcard style (postcard.js): big tilted postcards of real Photo Mode pictures, a teal note
// with the title, and the window that made the picture as a taped card. Photos are 2560x1440 (srcW defaults to
// 2560 there); UI cards are window screenshots at their own size (srcW given).
Square.slides('square_photo_mode', [
  { title: 'Every view,<br>a postcard', sub: 'Light, weather, looks, lenses, tours and wildlife in one window', style: 'postcard',
    media: { bg: 2, note: { x: 70, y: 150, w: 600, rot: -3 },
             photos: [
               { src: '05-neon-intersection.jpg', x: 1420, y: 360, w: 780, rot: 6, caption: 'Neon dusk', stamp: false },
               { src: '01-deer-herd-rain.jpg', x: 1500, y: 760, w: 760, rot: -5, caption: 'A herd in the rain', stamp: false },
               { src: '02-golden-town-market.jpg', x: 1110, y: 560, w: 900, rot: -1.5, caption: 'Golden hour over the market' } ] } },
  { title: 'Find the shot', sub: 'Random subjects and 15 photographer\'s shots: bridges, skylines, tunnel portals', style: 'postcard',
    media: { note: { x: 60, y: 70, w: 560, rot: -3 },
             photos: [{ src: '07-forest-mine-aerial.jpg', crop: [700, 380, 1600, 900], x: 1190, y: 520, w: 1240, rot: 2, caption: 'Ore train through the pines' }],
             uis: [{ src: 'ui-subjects.jpg', srcW: 1316, crop: [40, 300, 1210, 1000], x: 340, y: 800, w: 470, rot: -4 }] } },
  { title: 'Zoom 24 to 400 mm', sub: 'Lens view frames any object; long lenses stack the city', style: 'postcard',
    media: { note: { x: 60, y: 70, w: 560, rot: -3 },
             photos: [{ src: '03-telephoto-city.jpg', x: 1190, y: 520, w: 1240, rot: -2, caption: 'Downtown at 400 mm' }],
             uis: [{ src: 'ui-camera.jpg', srcW: 1338, crop: [60, 935, 1200, 860], x: 340, y: 810, w: 480, rot: 4 }] } },
  { title: 'Over 1,000 looks', sub: 'Mix a sky, a haze and a water look: Neon dusk, Golden glow, Dust storm', style: 'postcard',
    media: { note: { x: 60, y: 70, w: 560, rot: -3 },
             photos: [{ src: '05-neon-intersection.jpg', x: 1190, y: 520, w: 1240, rot: 2, caption: 'Neon dusk on the edge of town' }],
             uis: [{ src: 'ui-weather.jpg', srcW: 1362, crop: [60, 380, 1260, 480], x: 350, y: 820, w: 500, rot: -4 }] } },
  { title: 'Paint with light', sub: 'Golden and blue hour, time-lapse, season, sun direction', style: 'postcard',
    media: { note: { x: 60, y: 70, w: 560, rot: -3 },
             photos: [{ src: '06-snowy-ridges.jpg', x: 1190, y: 520, w: 1240, rot: -2, caption: 'First snow, low sun' }],
             uis: [{ src: 'ui-light.jpg', srcW: 1344, crop: [50, 380, 1210, 1050], x: 330, y: 800, w: 430, rot: 4 }] } },
  { title: 'Rain, haze and storms', sub: 'Clouds, cloud height, rain and a low cloud veil, live', style: 'postcard',
    media: { note: { x: 60, y: 70, w: 560, rot: -3 },
             photos: [{ src: '04-canyon-haze.jpg', x: 1190, y: 520, w: 1240, rot: 2, caption: 'Dust over the canyon' }],
             uis: [{ src: 'ui-weather.jpg', srcW: 1362, crop: [60, 1180, 1260, 600], x: 350, y: 820, w: 480, rot: -4 }] } },
  { title: 'Bring in the wildlife', sub: 'Herds, flocks and schools placed right where you look', style: 'postcard',
    media: { note: { x: 60, y: 70, w: 560, rot: -3 },
             photos: [{ src: '01-deer-herd-rain.jpg', x: 1190, y: 520, w: 1240, rot: -2, caption: 'Red deer, pink rain' }],
             uis: [{ src: 'ui-animals.jpg', srcW: 1340, crop: [40, 270, 1200, 760], x: 340, y: 820, w: 480, rot: 4 }] } },
  { title: 'Sit back for a tour', sub: 'Aerials over towns, rivers and rail, ground level, or a lens tour', style: 'postcard',
    media: { note: { x: 60, y: 70, w: 560, rot: -3 },
             photos: [{ src: '07-forest-mine-aerial.jpg', crop: [0, 0, 2560, 1440], x: 1190, y: 520, w: 1240, rot: 2, caption: 'Golden flight over the forest' }],
             uis: [{ src: 'ui-tour.jpg', srcW: 1386, crop: [40, 290, 1240, 880], x: 340, y: 815, w: 470, rot: -4 }] } },
  { title: 'Keep the shot', sub: 'Saved views and setups, High graphics, 1x, 2x and 4x screenshots', style: 'postcard',
    media: { bg: 1, note: { x: 60, y: 70, w: 560, rot: -3 },
             photos: [
               { src: '04-canyon-haze.jpg', x: 1380, y: 380, w: 820, rot: 5, caption: 'Saved view 3', stamp: false },
               { src: '02-golden-town-market.jpg', x: 1150, y: 600, w: 960, rot: -2, caption: 'Setup: Dust at sunset', capLeft: true } ],
             uis: [{ src: 'ui-settings.jpg', srcW: 1348, crop: [40, 260, 1200, 960], x: 340, y: 790, w: 440, rot: 4 },
                   { src: 'ui-views.jpg', srcW: 1452, crop: [60, 270, 1200, 520], x: 1640, y: 880, w: 400, rot: -5 }] } },
]);
