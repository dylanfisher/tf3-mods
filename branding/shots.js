// Gallery slides per mod: _metadata/1.png, 2.png, ... in slide order.
// Captures live in plans/<modId>/shots/ (never shipped); crop = [x, y, w, h] in capture pixels
// (5120x2880 Retina full-screen). Layouts (see slide.js):
//   single  { src, crop }
//   inset   { main: {src, crop}, inset: {src, crop}, insetW, at: 'tl'|'tr'|'bl'|'br' }
//   wipe    { before, after, crop, labels: [before, after], beforeCrop? }  same camera, 45° split
//           (beforeCrop re-frames "before" when the camera moved a little between captures;
//            split: share of the diagonal given to "before", default 0.5; darkChips: both labels dark)
//   stack   { items: [{src, crop}, {src, crop}], labels }      same UI, two states
//   table   { head: [col1, col2], rows: [[a, b], ...] }         text card, no capture
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
  { title: 'Every problem, one list', sub: 'Vehicles, lines, stations and fleet',
    media: { src: '01-full-list.jpg', crop: [1240, 684, 2648, 1320] } },
  { title: 'Always in view', sub: 'A problem count in the top-left corner',
    media: { layout: 'inset', at: 'tl', insetW: 460,
             main: { src: '02-fleet-list.jpg', crop: [0, 0, 4000, 2160] },
             inset: { src: '02-fleet-list.jpg', crop: [16, 8, 440, 112] } } },
  { title: 'Lines losing money', sub: 'A year of losses or empty seats, ranked by severity',
    media: { src: '04-economy.jpg', crop: [1240, 680, 2668, 900] } },
  { title: 'Off, List or Notify', sub: 'Choose how each alert reaches you',
    media: { src: '03-settings.jpg', crop: [1248, 944, 1080, 1076] } },
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
  // 'Find it' slide moved to the front: every slide number shifted, so delete all mod.io gallery
  // media before the next update (README "Gallery slides").
  { title: 'Find it in the Road menu', sub: 'Same tab as the game\'s own roundabout',
    media: { layout: 'inset', at: 'tr', insetW: 460,
             main: { src: '10-settings-main.jpg', crop: [980, 1600, 3160, 1200] },
             inset: { src: '10-settings-main.jpg', crop: [1372, 2408, 340, 212] } } },
  { title: 'Magic Roundabout', sub: 'Five mini roundabouts on a two-way ring',
    media: { src: '03-magic-closeup.jpg', crop: [320, 120, 4480, 2520] } },
  { title: 'Round, oval or mini', sub: 'Any size, up to six arms, one to four lanes',
    media: { src: '02-overview-variants.jpg', crop: [320, 560, 2880, 1840] } },
  { title: 'Pick a centre island', sub: 'Grass, trees, a fountain or paving',
    media: { src: '01-overview.jpg', crop: [80, 160, 2400, 1080] } },
  { title: 'Four menu entries', sub: 'Right next to the game\'s own roundabout',
    media: { layout: 'inset', at: 'tr', insetW: 620,
             main: { src: '10-settings-main.jpg', crop: [4008, 696, 1056, 1216] },
             inset: { src: '10-settings-main.jpg', crop: [1020, 2400, 1730, 240] } } },
  // Revision 3: "Through the centre" (published 3.png) removed and "Two new menu entries" replaced
  // by "Four menu entries", so slides 3-6 changed: delete mod.io media 3-6 before the update
  // (README "Gallery slides"). New slides below.
  { title: 'Roundabout interchange', sub: 'Two-bridge ring, dumbbell or peanut over a highway',
    media: { layout: 'inset', at: 'bl', insetW: 360,
             main: { src: '17-interchange-closeup.jpg', crop: [960, 120, 2800, 2000] },
             inset: { src: '13-menu-interchange-hover.jpg', crop: [4008, 696, 1056, 1160] } } },
  { title: 'Hamburger roundabouts', sub: 'A road straight through the ring, with splitter islands',
    media: { src: '15-oblique-hamburger.jpg', crop: [2000, 380, 2240, 1480] } },
  { title: 'Channelized junction', sub: 'Slip lanes and islands for a T or X junction',
    media: { layout: 'inset', at: 'bl', insetW: 360,
             main: { src: '14-top-down-variety.jpg', crop: [1668, 608, 1360, 880] },
             inset: { src: '12-menu-channel-hover.jpg', crop: [4008, 696, 1056, 1160] } } },
  { title: 'Mix and match', sub: 'Ovals, hamburgers, chains, junctions and interchanges',
    media: { src: '14-top-down-variety.jpg', crop: [600, 120, 3920, 2520] } },
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
  // 'Find it' slide moved to the front: every slide number shifted, so delete all mod.io gallery
  // media before the next update (README "Gallery slides").
  { title: 'Find it under Tools', sub: 'Road menu, Tools tab, by the Crossing Tool',
    media: { layout: 'inset', at: 'tr', insetW: 460,
             main: { src: '02-ring-select.jpg', crop: [980, 1600, 3160, 1200] },
             inset: { src: '02-ring-select.jpg', crop: [3760, 2408, 332, 212] } } },
  { title: 'Lanes that never cross', sub: 'Each entry lane gets its own ring lane and exit',
    media: { src: '03-junction-hover.jpg', crop: [1000, 400, 2760, 1760] } },
  { title: 'Junction or whole ring', sub: 'Apply or Reset with the Smart Lanes tool',
    media: { layout: 'inset', at: 'bl', insetW: 400,
             main: { src: '02-ring-select.jpg', crop: [1600, 560, 2560, 1600] },
             inset: { src: '02-ring-select.jpg', crop: [56, 1912, 880, 680] } } },
  { title: 'Every lane, shown', sub: 'Coloured lines show each connection',
    media: { src: '01-ring-lanes.jpg', crop: [1600, 760, 1760, 1160] } },
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
  { title: 'Where they\'re going', sub: 'Arrows from the stop to every destination',
    media: { layout: 'inset', at: 'tl', insetW: 540,
             main: { src: '01-station-arrows.jpg', crop: [461, 307, 3379, 2355] },
             inset: { src: '01-station-arrows.jpg', crop: [3853, 38, 1178, 358] } } },
  { title: 'One row in the window', sub: 'Tick a terminal, or all of them',
    media: { layout: 'stack', labels: ['Off', 'On'],
             // Same size, On framed 16 px lower: Off stops above the first terminal's text, On still shows the summary.
             items: [{ src: '02-station-row.jpg', crop: [3853, 38, 1178, 324] },
                     { src: '01-station-arrows.jpg', crop: [3853, 54, 1178, 324] }] } },
  { title: 'Off until you ask', sub: 'Nothing on the map until you tick a box',
    media: { layout: 'wipe', labels: ['Off', 'On'], split: 0.35,
             before: '02-station-row.jpg', after: '01-station-arrows.jpg',
             crop: [461, 307, 3379, 2355] } },
  { title: 'Like arrows?', sub: 'Good news: about thirty more per bus stop',
    media: { src: '01-station-arrows.jpg', crop: [768, 512, 1792, 1152] } },
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
