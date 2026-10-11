// One entry per mod: cover data + pictogram. Order = gallery order.
//   id       modId (folder in mods/); render_covers.py writes mods/<id>/_metadata/0.png
//   name     display name, same as _metadata/modinfo.json "name"
//   tagline  short line under the title (max ~32 chars)
//   accent   the mod's accent colour, used inside the pictogram
//   glyph    returns SVG markup in an 800x800 box; use the classes from cover.js
//            (ink / acc / cut / cutf / sink / sacc / scut / sep / under) and helpers on S.
//   optional titleLines (fixed title lines instead of the automatic wrap) and overlay(S, o) (markup in cover
//   coordinates drawn above the pictogram; o.dx = pictogram shift when the title is off). Both are used by
//   Square.stateCover (README "State series"); one-off mods normally need neither.
Square.register({
  id: 'square_bigger_line_dots', name: 'Bigger Line Dots', tagline: 'Line dots you can actually see', accent: '#4FA3E0',
  glyph: S => `
    <g opacity=".45">
      <rect class="ink" x="130" y="120" width="230" height="74" rx="14"/>
      ${S.LINE_COLORS.map((c, i) => `<rect x="${157 + i * 49}" y="142" width="30" height="30" rx="7" fill="${c}"/>`).join('')}
    </g>
    <path class="sink" d="M380 160 Q 470 160 500 248" stroke-width="22" stroke-linecap="round"/>
    <path class="sink" d="M462 236 L502 262 L520 216" stroke-width="22" stroke-linecap="round" stroke-linejoin="round"/>
    <rect class="ink" x="100" y="300" width="600" height="170" rx="30"/>
    ${S.LINE_COLORS.map((c, i) => `<rect x="${129 + i * 143}" y="329" width="112" height="112" rx="26" fill="${c}"/>`).join('')}
    <rect class="ink" x="384" y="470" width="32" height="90"/>
    <rect class="ink" x="250" y="556" width="300" height="84" rx="16"/>
    ${S.ground(80, 640, 670)}`,
});

Square.register({
  id: 'square_industry_flows', name: 'Industry Flows', tagline: 'Every cargo flow at once', accent: '#33C2B0',
  glyph: S => `
    ${S.factory(80, 320)}
    ${S.ground(50, 400)}
    <path class="sacc" d="M425 520 C 560 520, 560 250, 680 250" stroke-width="32" stroke-linecap="round"/>
    <path class="sacc" d="M425 540 C 560 540, 570 440, 680 440" stroke-width="32" stroke-linecap="round"/>
    <path class="sacc" d="M425 560 C 560 560, 560 630, 680 630" stroke-width="32" stroke-linecap="round"/>
    ${S.arrowHead(680, 250)}${S.arrowHead(680, 440)}${S.arrowHead(680, 630)}`,
});

Square.register({
  id: 'square_industry_production_label', name: 'Industry Production Label', tagline: 'Live production on every label', accent: '#8BD450',
  glyph: S => `
    <rect class="ink" x="170" y="100" width="460" height="210" rx="42"/>
    <path class="ink" d="M355 300 L400 360 L445 300 Z"/>
    <rect class="acc" x="205" y="137" width="390" height="136" rx="68"/>
    <path class="cutf" d="M240 248 V186 L272 166 V186 L304 166 V186 L336 166 V248 Z"/>
    <rect class="cutf" x="246" y="152" width="16" height="40" rx="3"/>
    <text class="t cutf" x="472" y="248" text-anchor="middle" font-size="108" font-weight="800">425</text>
    ${S.factory(235, 385)}
    ${S.ground(150, 500, 700)}`,
});

Square.register({
  id: 'square_no_factory_passengers', name: 'No Factory Passengers', tagline: 'Keep commuters off cargo stops', accent: '#E5554F',
  glyph: S => `
    ${S.factory(410, 340, .95)}
    ${S.ground(60, 680, 650)}
    <rect class="ink" x="168" y="340" width="124" height="180" rx="52"/>
    <rect class="ink" x="178" y="460" width="46" height="170" rx="23"/>
    <rect class="ink" x="236" y="460" width="46" height="170" rx="23"/>
    <circle class="scut" cx="230" cy="430" r="200" stroke-width="80"/>
    <circle class="sacc" cx="230" cy="430" r="200" stroke-width="44"/>
    <path class="sacc" d="M89 289 L371 571" stroke-width="44"/>
    <circle class="ink sep" cx="230" cy="215" r="58"/>`,
});

Square.register({
  id: 'square_problem_radar', name: 'Problem Radar', tagline: 'Every problem in one window', accent: '#F1B43D',
  glyph: S => `
    <g opacity=".5">
      <circle class="sink" cx="400" cy="420" r="320" stroke-width="16"/>
      <circle class="sink" cx="400" cy="420" r="220" stroke-width="14"/>
      <circle class="sink" cx="400" cy="420" r="120" stroke-width="12"/>
    </g>
    <path class="sink" d="M80 420 H720 M400 100 V740" stroke-width="8" opacity=".3"/>
    <path class="acc" d="M400 420 L400 100 A320 320 0 0 1 626 194 Z" opacity=".35"/>
    <path class="sacc" d="M400 420 L626 194" stroke-width="14" stroke-linecap="round"/>
    <circle class="ink" cx="400" cy="420" r="24"/>
    <circle class="ink" cx="250" cy="330" r="17" opacity=".85"/>
    <circle class="ink" cx="530" cy="575" r="17" opacity=".85"/>
    <circle class="ink" cx="300" cy="620" r="13" opacity=".6"/>
    <path class="acc sep" d="M540 180 Q548 168 556 180 L626 302 Q632 316 618 316 L462 316 Q448 316 454 302 Z"/>
    <rect class="cutf" x="530" y="215" width="20" height="56" rx="10"/>
    <circle class="cutf" cx="540" cy="292" r="12"/>`,
});

Square.register({
  id: 'square_better_minimap', name: 'Better Minimap', tagline: 'See roads, rails and towns,\nfilter by industry', accent: '#E8B740',
  // Exception to the flat-pictogram rule: the real map window (Ind, Net and Viz on) as a large
  // rounded card, a crop of 23-ind-viz.jpg with a strip of the scene on its left. Coordinates reach
  // outside the 800 box so the card spans x 1180-1880, y 40-1040 on the cover, across the diagonal.
  glyph: S => `
    <defs>
      <clipPath id="bmCard"><rect x="-62.5" y="-237.5" width="875" height="1250" rx="30"/></clipPath>
      <filter id="bmShadow" x="-10%" y="-10%" width="120%" height="120%"><feDropShadow dx="0" dy="14" stdDeviation="22" flood-color="#000" flood-opacity=".45"/></filter>
    </defs>
    <rect x="-62.5" y="-237.5" width="875" height="1250" rx="30" fill="#18202a" filter="url(#bmShadow)"/>
    <g clip-path="url(#bmCard)"><svg x="-62.5" y="-237.5" width="875" height="1250" viewBox="3635 160 1470 2100" preserveAspectRatio="xMidYMid slice">
      <image href="../plans/square_better_minimap/shots/23-ind-viz.jpg" width="5120" height="2880"/>
    </svg></g>`,
});

Square.register({
  id: 'square_roundabouts', name: 'Roundabouts & Interchanges', tagline: 'Rings, junctions, interchanges', accent: '#E8833A',
  // Top view of the Magic Roundabout entry: five mini rings (knocked-out islands) on a central
  // ring, one arm each, around an accent centre island. Stands for the whole family of shapes.
  glyph: S => {
    const c = 400, d = 215;
    const at = (deg, r) => [c + r * Math.cos(deg * Math.PI / 180), c - r * Math.sin(deg * Math.PI / 180)];
    const angles = [90, 162, 234, 306, 18];
    const arms = angles.map(deg => {
      const [x, y] = at(deg, d);
      return `<rect class="ink" x="${(x - 42).toFixed(1)}" y="${(y - 42).toFixed(1)}" width="${(390 - d + 42).toFixed(1)}" height="84" rx="30"
        transform="rotate(${-deg} ${x.toFixed(1)} ${y.toFixed(1)})"/>`;
    }).join('');
    const minis = angles.map(deg => {
      const [x, y] = at(deg, d);
      return `<circle class="ink sep" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="84"/>
      <circle class="cut" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="36"/>`;
    }).join('');
    return `
    ${arms}
    <circle class="sink" cx="${c}" cy="${c}" r="${d}" stroke-width="60"/>
    ${minis}
    <circle class="acc sep" cx="${c}" cy="${c}" r="104"/>`;
  },
});

Square.register({
  id: 'square_one_way_roads', name: 'Early One-way Roads', tagline: 'One-way streets from day one', accent: '#9B7BE0',
  // Top view of a two-lane road with a dashed centre line; both lanes carry an
  // accent arrow pointing the same way.
  glyph: S => {
    const arrow = x => `
    <rect class="acc" x="${x - 28}" y="330" width="56" height="320" rx="20"/>
    <path class="acc" d="M${x} 170 L${x + 78} 340 Q${x + 86} 362 ${x + 60} 362 H${x - 60} Q${x - 86} 362 ${x - 78} 340 Z"/>`;
    return `
    <rect class="ink" x="150" y="40" width="500" height="720" rx="48"/>
    ${[90, 280, 470, 660].map(y => `<rect class="cut" x="388" y="${y}" width="24" height="90" rx="12"/>`).join('')}
    ${arrow(270)}${arrow(530)}`;
  },
});

Square.register({
  id: 'square_bulk_bulldozer', name: 'Bulk Bulldozer', tagline: 'Paint to bulldoze in bulk', accent: '#F4D32B',
  // Side view of a bulldozer (blade forward, to the left) inside the dashed accent brush ring,
  // the same motif as the in-game menu icon (tools/render_icon_square_bulk_bulldozer.py).
  glyph: S => `
    <circle class="sacc" cx="400" cy="400" r="340" stroke-width="30" stroke-linecap="round" stroke-dasharray="40 49"/>
    <g transform="translate(25 -40)">
      <rect class="ink" x="420" y="240" width="160" height="160" rx="24"/>
      <rect class="cut" x="448" y="266" width="104" height="72" rx="14"/>
      <rect class="ink" x="310" y="300" width="30" height="90" rx="13"/>
      <rect class="ink" x="270" y="370" width="320" height="100" rx="22"/>
      <rect class="ink sep" x="245" y="470" width="370" height="110" rx="55"/>
      ${[310, 395, 480, 555].map(x => `<circle class="cut" cx="${x}" cy="525" r="${x === 555 ? 24 : 28}"/>`).join('')}
      <path class="sink" d="M285 430 L195 470" stroke-width="34" stroke-linecap="round"/>
      <path class="acc sep" d="M145 316 Q145 304 157 303 L198 300 Q210 299 211 311 L226 578 Q227 592 213 593 L148 598 Q134 599 135 585 Q178 455 145 316 Z"/>
    </g>`,
});

Square.register({
  id: 'square_full_refund', name: 'Full Refund Window', tagline: 'Undo mistakes for free', accent: '#E0609B',
  // A coin inside a counter-clockwise return arrow: the money comes back.
  glyph: S => `
    <circle class="ink" cx="400" cy="400" r="215"/>
    <circle class="cut" cx="400" cy="400" r="165"/>
    <circle class="ink" cx="400" cy="400" r="125"/>
    <path class="sacc" d="M400 60 A340 340 0 1 1 170 650" fill="none" stroke-width="44" stroke-linecap="round"/>
    <path class="acc" d="M100 580 L230 610 L130 710 Z"/>`,
});

Square.register({
  id: 'square_line_revert', name: 'Line Editor Undo', tagline: 'Undo and redo line stop edits', accent: '#C964E8',
  // A counter-clockwise undo hook arrow over a line with three stops, one stop in accent (the edit
  // being taken back).
  glyph: S => `
    <path class="sacc" d="M250 210 H450 A155 155 0 0 1 450 520 H330" stroke-width="64" stroke-linecap="round" stroke-linejoin="round"/>
    <path class="acc" d="M100 210 L268 100 Q290 86 290 112 V308 Q290 334 268 320 Z" stroke="var(--acc)" stroke-width="24" stroke-linejoin="round"/>
    <rect class="ink" x="170" y="670" width="460" height="40" rx="20"/>
    ${[170, 400, 630].map((x, i) => `<circle class="${i === 1 ? 'acc' : 'ink'} sep" cx="${x}" cy="690" r="62"/>
    <circle class="cut" cx="${x}" cy="690" r="24"/>`).join('')}`,
});

Square.register({
  id: 'square_smart_lanes', name: 'Smart Lanes', tagline: 'Lane discipline on roundabouts', accent: '#3FD6EE',
  // Top view of a two-lane ring with a dashed lane divider and a two-lane exit arm at the top: two
  // accent arrows leave the ring side by side, each from its own ring lane into its own exit lane.
  glyph: S => {
    const head = x => `<path class="acc" d="M${x - 36} 128 L${x} 44 L${x + 36} 128 Z"/>`;
    return `
    <rect class="ink" x="300" y="20" width="200" height="220" rx="30"/>
    <circle class="sink" cx="400" cy="450" r="230" stroke-width="170"/>
    <circle class="scut" cx="400" cy="450" r="230" stroke-width="14" stroke-dasharray="36 34"/>
    <path class="sacc" d="M636 586 A272 272 0 0 0 440 181 L440 120" stroke-width="38" stroke-linecap="round" stroke-linejoin="round"/>
    <path class="sacc" d="M563 544 A188 188 0 0 0 360 266 L360 120" stroke-width="38" stroke-linecap="round" stroke-linejoin="round"/>
    ${head(440)}${head(360)}`;
  },
});

Square.register({
  id: 'square_better_bus_overlay', name: 'Better Bus Overlay', tagline: 'Lines, gaps and busy stops', accent: '#5B7CFA',
  // Three line routes in line colours sweep across behind three stop pins (the game's HUD pin shape: rounded
  // square with a pointer tail, a bus front knocked out) coloured quiet (the accent blue), busy yellow and crowded
  // red: the Lines window busy scale.
  glyph: S => {
    const pin = (x, y, c) => `
      <path d="M${x - 78} ${y - 150} h156 a26 26 0 0 1 26 26 v130 a26 26 0 0 1 -26 26 h-52 l-26 34 l-26 -34 h-52 a26 26 0 0 1 -26 -26 v-130 a26 26 0 0 1 26 -26 z" fill="${c}" class="sep"/>
      <rect class="cut" x="${x - 40}" y="${y - 124}" width="80" height="100" rx="18"/>
      <rect x="${x - 26}" y="${y - 112}" width="52" height="38" rx="6" fill="${c}"/>
      <circle cx="${x - 20}" cy="${y - 46}" r="9" fill="${c}"/><circle cx="${x + 20}" cy="${y - 46}" r="9" fill="${c}"/>`;
    return `
    ${S.LINE_COLORS.slice(0, 3).map((c, i) => `<path d="M40 ${330 + i * 150} C 260 ${210 + i * 150}, 520 ${490 + i * 120}, 760 ${330 + i * 150}" fill="none" stroke="${c}" stroke-width="40" stroke-linecap="round" opacity=".5"/>`).join('')}
    ${pin(180, 360, 'var(--acc)')}
    ${pin(400, 560, '#F5C733')}
    ${pin(620, 330, '#E34038')}`;
  },
});

Square.register({
  id: 'square_supply_gaps', name: 'Supply Gap Overview', tagline: 'Find buildings your routes miss', accent: '#C2E83A',
  // Three town buildings on a base line: an accent down arrow over the left house (no delivering stop
  // in range) and an accent exclamation over the right one (in range, stock empty); the middle block is served.
  glyph: S => {
    const house = cx => `
    <path class="ink" d="M${cx - 112} 470 L${cx} 352 L${cx + 112} 470 Z" stroke="var(--ink)" stroke-width="28" stroke-linejoin="round"/>
    <rect class="ink" x="${cx - 95}" y="450" width="190" height="210" rx="14"/>
    <rect class="cut" x="${cx - 26}" y="560" width="52" height="100" rx="10"/>`;
    return `<g transform="translate(20 70)">
    ${house(150)}${house(650)}
    <rect class="ink sep" x="300" y="330" width="200" height="330" rx="16"/>
    ${[380, 470, 560].map(y => [345, 418].map(x => `<rect class="cut" x="${x}" y="${y}" width="38" height="50" rx="8"/>`).join('')).join('')}
    ${S.ground(40, 720, 660)}
    <rect class="acc" x="118" y="0" width="64" height="170" rx="20"/>
    <path class="acc" d="M150 276 L64 156 H236 Z" stroke="var(--acc)" stroke-width="24" stroke-linejoin="round"/>
    <rect class="acc" x="618" y="0" width="64" height="186" rx="32"/>
    <circle class="acc" cx="650" cy="250" r="38"/></g>`;
  },
});

Square.register({
  id: 'square_blank_slate', name: 'Blank Slate: Empty Flat Test Map', tagline: 'A flat, empty island to test on', accent: '#7CF0B4',
  // Top view of the generated map: an accent sea with two wave knock-outs around a blank ink island
  // (the rounded-square plateau of the heightmap).
  glyph: S => `
    <rect class="acc" x="90" y="90" width="620" height="620" rx="80"/>
    <rect class="ink sep" x="200" y="200" width="400" height="400" rx="60"/>
    <path class="scut" d="M250 145 q30 -22 60 0 t60 0" fill="none" stroke-width="16" stroke-linecap="round"/>
    <path class="scut" d="M430 655 q30 -22 60 0 t60 0" fill="none" stroke-width="16" stroke-linecap="round"/>`,
});

Square.register({
  id: 'square_passenger_destinations', name: 'Passenger Destinations', tagline: 'See where passengers are going', accent: '#FF8A65',
  // A passenger on the left with three accent arrows fanning out to three small houses: where the
  // people waiting at a stop are headed.
  glyph: S => {
    const ox = 290, oy = 420;
    const house = (cx, cy) => `
    <path class="ink" d="M${cx - 92} ${cy - 20} L${cx} ${cy - 100} L${cx + 92} ${cy - 20} Z" stroke="var(--ink)" stroke-width="26" stroke-linejoin="round"/>
    <rect class="ink" x="${cx - 74}" y="${cy - 36}" width="148" height="126" rx="12"/>
    <rect class="cut" x="${cx - 22}" y="${cy + 24}" width="44" height="66" rx="9"/>`;
    const arrow = (tx, ty) => {
      const a = Math.atan2(ty - oy, tx - ox), deg = a * 180 / Math.PI;
      const ex = tx - 20 * Math.cos(a), ey = ty - 20 * Math.sin(a);
      return `<path class="sacc" d="M${ox} ${oy} L${ex.toFixed(1)} ${ey.toFixed(1)}" stroke-width="44" stroke-linecap="round"/>
    <g transform="rotate(${deg.toFixed(2)} ${tx} ${ty}) translate(${tx} ${ty}) scale(1.45) translate(${-tx} ${-ty})">${S.arrowHead(tx, ty)}</g>`;
    };
    return `
    ${house(650, 130)}${house(690, 420)}${house(650, 710)}
    ${arrow(488, 190)}${arrow(500, 420)}${arrow(488, 650)}
    <rect class="ink sep" x="90" y="340" width="140" height="200" rx="58"/>
    <rect class="ink" x="100" y="470" width="52" height="190" rx="26"/>
    <rect class="ink" x="168" y="470" width="52" height="190" rx="26"/>
    <circle class="ink sep" cx="160" cy="252" r="66"/>`;
  },
});

Square.register({
  id: 'square_stress_test', name: 'Stress Test Debug Tool', tagline: 'A dense, busy city to benchmark', accent: '#F048D8',
  // A load gauge with its needle pegged in the accent red zone, over a dense city skyline: the game
  // under maximum load.
  glyph: S => {
    const cx = 400, cy = 330, r = 240;
    const pt = (deg, rr) => [cx + rr * Math.cos(deg * Math.PI / 180), cy - rr * Math.sin(deg * Math.PI / 180)];
    const f = ([x, y]) => `${x.toFixed(1)} ${y.toFixed(1)}`;
    const arc = (a0, a1, cls, w = 72) => `<path class="${cls}" d="M${f(pt(a0, r))} A${r} ${r} 0 0 1 ${f(pt(a1, r))}" stroke-width="${w}" stroke-linecap="round"/>`;
    const n = 18;  // needle angle: pegged inside the red zone
    const needle = `M${f(pt(n + 90, 40))} L${f(pt(n, 196))} L${f(pt(n - 90, 40))} Z`;
    const bars = [[110, 170], [196, 250], [282, 190], [368, 280], [454, 220], [540, 270], [626, 200]];
    const towers = bars.map(([x, h]) => `<rect class="ink" x="${x}" y="${700 - h}" width="64" height="${h}" rx="12"/>
      ${Array.from({ length: Math.floor((h - 30) / 64) }, (_, i) =>
        `<rect class="cut" x="${x + 20}" y="${700 - h + 26 + i * 64}" width="24" height="32" rx="7"/>`).join('')}`).join('');
    return `
    ${towers}
    ${S.ground(80, 640, 700)}
    ${arc(180, 60, 'sink')}
    ${arc(40, 0, 'scut', 108)}${arc(40, 0, 'sacc')}
    <path class="ink" d="${needle}" stroke="var(--ink)" stroke-width="28" stroke-linejoin="round"/>
    <circle class="ink" cx="${cx}" cy="${cy}" r="60"/>
    <circle class="cut" cx="${cx}" cy="${cy}" r="20"/>`;
  },
});

Square.register({
  id: 'square_line_manager_plus', name: 'Line Manager Plus', tagline: 'Undo edits, know where you send', accent: '#D9B98C',
  // Both features over one line with three stops: Line Editor Undo's counter-clockwise undo hook (accent, top
  // left) and Send to Line Info's ink tooltip bubble with an accent "i" and three knocked-out text rows, its tail
  // pointing at the line (top right).
  glyph: S => `
    <rect class="ink" x="100" y="660" width="600" height="40" rx="20"/>
    ${[160, 400, 640].map(x => `<circle class="ink sep" cx="${x}" cy="680" r="56"/>
    <circle class="cut" cx="${x}" cy="680" r="20"/>`).join('')}
    <path class="sacc" d="M170 220 H220 A92 92 0 0 1 220 404 H160" stroke-width="50" stroke-linecap="round" stroke-linejoin="round"/>
    <path class="acc" d="M50 220 L176 140 Q194 130 194 150 V290 Q194 310 176 300 Z" stroke="var(--acc)" stroke-width="20" stroke-linejoin="round"/>
    <path class="ink sep" d="M480 110 H720 A40 40 0 0 1 760 150 V390 A40 40 0 0 1 720 430 H600 L540 520 V430 H480 A40 40 0 0 1 440 390 V150 A40 40 0 0 1 480 110 Z"/>
    <circle class="acc" cx="502" cy="182" r="28"/>
    <rect class="acc" x="479" y="232" width="46" height="150" rx="21"/>
    <rect class="cut" x="560" y="168" width="160" height="34" rx="17"/>
    <rect class="cut" x="560" y="252" width="130" height="34" rx="17"/>
    <rect class="cut" x="560" y="336" width="95" height="34" rx="17"/>`,
});

Square.register({
  id: 'square_line_rate_matcher', name: 'Line Rate Matcher', tagline: 'Right-size lines to their supply', accent: '#8A7FD1',
  // Supply equals transport: an industry (left) and a cargo ship on the water (right) with an accent equals sign
  // between them, i.e. the line's Rate matched to what the producer makes.
  glyph: S => `
    ${S.factory(0, 336, .78)}
    ${S.ground(-10, 292, 570)}
    <rect class="acc" x="318" y="404" width="108" height="46" rx="23"/>
    <rect class="acc" x="318" y="492" width="108" height="46" rx="23"/>
    <rect class="ink" x="536" y="330" width="44" height="90" rx="12"/>
    <rect class="ink" x="508" y="390" width="120" height="120" rx="18"/>
    <rect class="cut" x="528" y="420" width="32" height="32" rx="8"/>
    <rect class="cut" x="576" y="420" width="32" height="32" rx="8"/>
    <rect class="ink" x="646" y="440" width="114" height="70" rx="12"/>
    <path class="ink" d="M478 520 H800 L754 592 Q746 604 730 604 H536 Q520 604 513 592 Z"/>
    <path class="sink" d="M494 660 q 38 -26 76 0 t 76 0 t 76 0 t 76 0" stroke-width="22" stroke-linecap="round"/>`,
});

// US State Names series: one line per state, same cover every time (cover.js stateCover, README "State series").
Square.stateCover({
  id: 'square_names_us_washington', state: 'Washington', flag: 'us_washington.svg', flagAspect: 1.6, accent: '#00843D',
});
Square.stateCover({
  id: 'square_names_us_arizona', state: 'Arizona', flag: 'us_arizona.svg', flagAspect: 1.5, accent: '#CE5C17',
});
Square.stateCover({
  id: 'square_names_us_florida', state: 'Florida', flag: 'us_florida.svg', flagAspect: 1.5, accent: '#C60013',
});
Square.stateCover({
  id: 'square_names_us_colorado', state: 'Colorado', flag: 'us_colorado.svg', flagAspect: 1.5, accent: '#00205B',
});
Square.stateCover({
  id: 'square_names_us_california', state: 'California', flag: 'us_california.svg', flagAspect: 1.5, accent: '#5C462B',
});
Square.stateCover({
  id: 'square_names_us_texas', state: 'Texas', flag: 'us_texas.svg', flagAspect: 1.5, accent: '#BF0A30',
});
Square.stateCover({
  id: 'square_names_us_alaska', state: 'Alaska', flag: 'us_alaska.svg', flagAspect: 1.416, accent: '#FFB612',
});
Square.stateCover({
  id: 'square_names_us_new_york', state: 'New York', flag: 'us_new_york.svg', flagAspect: 2.0, accent: '#ECC875',
});
Square.stateCover({
  id: 'square_names_us_minnesota', state: 'Minnesota', flag: 'us_minnesota.svg', flagAspect: 1.6667, accent: '#52C9E8',
});
Square.stateCover({
  id: 'square_names_us_new_mexico', state: 'New Mexico', flag: 'us_new_mexico.svg', flagAspect: 1.5, accent: '#0095B6',
});
Square.stateCover({
  id: 'square_names_us_oregon', state: 'Oregon', flag: 'us_oregon.svg', flagAspect: 1.5, accent: '#2C5E3F',
});
Square.stateCover({
  id: 'square_names_us_pennsylvania', state: 'Pennsylvania', flag: 'us_pennsylvania.svg', flagAspect: 1.3704, accent: '#1F5290',
});
Square.stateCover({
  id: 'square_names_us_hawaii', state: 'Hawaii', flag: 'us_hawaii.svg', flagAspect: 2.0, accent: '#D63384',
});

// Local SQ Opt forks (gitignored, never uploaded): fork-orange field instead of the teal. README "Local forks".
Square.forkCover({
  id: 'square_opt_zhenya_auto_assign_terminals', name: 'SQ Opt: Auto Assign Terminals',
});

// DEV mods (test harnesses and probes, NOT_FOR_UPLOAD.txt): grey field instead of the teal, shared flask. README "DEV mods".
Square.devCover({
  id: 'square_aat_perftest', name: 'DEV AAT Perf Test', group: 'perf', tagline: 'Timed original vs optimized',
});
Square.devCover({
  id: 'square_hitch_probe', name: 'DEV Hitch Probe', group: 'perf', tagline: 'Do script pauses drop frames?',
});
Square.devCover({
  id: 'square_line_revert_probe', name: 'DEV Line Revert Probe', group: 'lines',
});
Square.devCover({
  id: 'square_roundabouts_lanes_probe', name: 'DEV Roundabouts Lane Probe', group: 'roundabouts',
});
Square.devCover({
  id: 'square_roundabouts_probe', name: 'DEV Roundabouts Probe', group: 'roundabouts',
});
Square.devCover({
  id: 'square_sqperf_all', name: 'DEV SQPERF: all mods', group: 'perf', tagline: 'Perf log on for every mod',
  titleLines: ['DEV SQPERF:', 'all mods'],  // the automatic wrap leaves "mods" alone on line 2
});
Square.devCover({
  id: 'square_sqperf_probe', name: 'DEV SQPERF Probe', group: 'perf', tagline: 'Clock timing in HUD scripts',
});
Square.devCover({
  id: 'square_town_street_names_probe', name: 'DEV Town Street Names Probe', group: 'names',
});
