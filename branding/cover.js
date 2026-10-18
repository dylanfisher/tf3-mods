// "square" house style for mod covers (direction B2, Diagonal Split).
// Plain browser script, no build step: loaded by index.html (gallery) and render.html (PNG export).
// Covers are 1920x1080 SVG. Per-mod data and pictograms live in mods.js.
(function () {
  const BRAND = '#2FA48F';  // family colour: left (title) side of every cover
  const DARK = '#18202a';   // right (pictogram) side
  const INK_ON_BRAND = '#0f1d1b';
  const LINE_COLORS = ['#E5554F', '#4FA3E0', '#3CC48A', '#F2B33D'];
  // Local "SQ Opt" forks of other authors' mods (never uploaded): same layout, this colour instead of the teal,
  // so a local override is obvious at a glance in the mod list.
  const FORK = '#E2873B';
  // DEV mods (test harnesses and probes, never uploaded): same layout, a neutral steel grey instead of the teal,
  // so "not a real mod" reads at a glance. No accent and no state colour is grey.
  const DEV = '#8E9BAE';
  // DEV groups: DEV mods of one kind share a colour. The title field is a diagonal gradient from the group's
  // unsaturated `from` (top left, behind the text) to its saturated `to` (bottom right); the stripe and the
  // flask liquid use `to`. The shared layout and flask keep them one DEV family. Ungrouped DEV mods keep the grey.
  const DEV_GROUPS = {
    perf:        { from: '#8FA9C2', to: '#3F9BF0' },  // perf harnesses and SQPERF (blue)
    roundabouts: { from: '#BFAE7E', to: '#E8C21E' },  // Roundabouts & Interchanges probes (yellow; away from the fork orange)
    lines:       { from: '#AE9DC2', to: '#B66EF2' },  // line tools probes (violet)
    names:       { from: '#95AE8B', to: '#6CCB45' },  // town and street names probes (green)
  };

  // Pictogram CSS: glyphs use these classes and never hard-code the theme colours.
  //   ink  = main shape colour (white-ish), acc = the mod's accent, cut = the surface behind the glyph.
  const SVG_CSS = `
    .under{fill:var(--cut)} .ink{fill:var(--ink)} .acc{fill:var(--acc)} .cut,.cutf{fill:var(--cut)}
    .sink{fill:none;stroke:var(--ink)} .sacc{fill:none;stroke:var(--acc)} .scut{fill:none;stroke:var(--cut)}
    .sep{stroke:var(--cut);stroke-width:20;paint-order:stroke}
    .t{font-family:Overpass,'Helvetica Neue',Arial,sans-serif} .m{font-family:'Overpass Mono',Menlo,monospace}`;

  const DEFS = `
    <linearGradient id="sqSheen" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".14"/><stop offset=".55" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".18"/></linearGradient>`;

  // ---------- Pictogram helpers (800x800 glyph box) ----------
  const factory = (x, y, s = 1) => `
    <g transform="translate(${x} ${y}) scale(${s})">
      <rect class="ink" x="22" y="0" width="52" height="150" rx="8"/>
      <path class="ink" d="M0 300 V110 L110 40 V110 L220 40 V110 L330 40 V300 Z"/>
      <rect class="cut" x="40" y="180" width="54" height="64" rx="8"/>
      <rect class="cut" x="138" y="180" width="54" height="64" rx="8"/>
      <rect class="cut" x="236" y="180" width="54" height="64" rx="8"/>
    </g>`;
  const ground = (x, w, y = 640) => `<rect class="ink" x="${x}" y="${y}" width="${w}" height="24" rx="12"/>`;
  const arrowHead = (x, y) => `<path class="acc" d="M${x - 12} ${y - 40} L${x + 48} ${y} L${x - 12} ${y + 40} Z"/>`;

  // ---------- Layout ----------
  // Text wraps to the room left of the diagonal at each line's baseline, so lines higher up
  // (where the teal side is wider) hold more. Widths are estimated per character from the
  // rendered Overpass sizes (title 800/130 px ~66 px, tagline 600/74 px ~37 px).
  const TITLE = { size: 130, lead: 132, x: 108, ch: 66 };
  const TAG = { size: 74, lead: 86, gap: 120, x: 114, ch: 37 };
  const CLEAR = 90;  // gap kept between a line's end and the diagonal, measured at the descender
  const room = (e, x, y, ch) => Math.floor((e - (y + 30) - CLEAR - x) / ch);
  function wrap(text, e, x, y0, lead, ch) {
    const out = []; let cur = '';
    for (const w of text.split(' ')) {
      const max = room(e, x, y0 + out.length * lead, ch);
      if (cur && (cur + ' ' + w).length > max) { out.push(cur); cur = w; } else cur = cur ? cur + ' ' + w : w;
    }
    return [...out, cur];
  }
  // A tagline that doesn't fit on one line splits into two with the longer half on top:
  // at the first space past the middle, or the last space that still fits if that one doesn't.
  function splitTagline(text, max) {
    if (text.includes('\n')) return text.split('\n');  // a manual break wins over the estimate
    if (text.length <= max) return [text];
    const spaces = [...text].map((c, i) => c === ' ' ? i : -1).filter(i => i > 0);
    const fits = spaces.filter(i => i <= max);
    const at = spaces.find(i => i > text.length / 2 && i <= max) ?? fits[fits.length - 1] ?? spaces[0];
    return at === undefined ? [text] : [text.slice(0, at), text.slice(at + 1)];
  }
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

  // ---------- Deprecated sash ----------
  // Mods we no longer maintain get a red sash across the top-right corner, drawn above everything else. The cover
  // keeps its colours so it stays recognisable; the sash only covers the corner of the pictogram.
  // mod.deprecated: true, or the replacement mod's display name ("Use <name>" on a second line).
  const DEPRECATED = '#D9443A';
  function sash(deprecated) {
    const a = 640, b = 420, c = (a + b) / 2;  // band between the lines x - y = 1920 - a and x - y = 1920 - b
    const use = typeof deprecated === 'string' ? `Use ${deprecated}` : '';
    // Overpass squeezed with textLength only when the per-character estimate overflows the band.
    const fit = (s, size, max, em) => (s.length * size * em > max ? `textLength="${max}" lengthAdjust="spacingAndGlyphs"` : '');
    return `
      <defs><filter id="sqSashShadow" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity=".5"/></filter></defs>
      <g filter="url(#sqSashShadow)"><path d="M${1920 - a} 0 H${1920 - b} L1920 ${b} V${a} Z" fill="${DEPRECATED}"/></g>
      <path d="M${1920 - a + 14} 0 L1920 ${a - 14} M${1920 - b - 14} 0 L1920 ${b + 14}" stroke="#fff" stroke-opacity=".55" stroke-width="5"/>
      <g class="t" transform="translate(${1920 - c / 2} ${c / 2}) rotate(45)" text-anchor="middle" fill="#fff">
        <text y="${use ? 6 : 30}" font-size="72" font-weight="800" letter-spacing="5" ${fit('DEPRECATED', 72, 520, 0.72)}>DEPRECATED</text>
        ${use ? `<text y="58" font-size="36" font-weight="600" fill-opacity=".9" ${fit(use, 36, 520, 0.6)}>${esc(use)}</text>` : ''}
      </g>`;
  }

  const glyph = (mod, x, y, size) =>
    `<g transform="translate(${x} ${y}) scale(${size / 800})">${mod.glyph(Square)}</g>`;

  // opts: { text: true }
  function render(mod, opts = {}) {
    const o = { text: true, ...opts };
    const vars = `--ink:#eef2f6;--acc:${mod.accent};--cut:${DARK}`;
    const field = mod.field || BRAND;
    const e = o.text ? 1540 : 1180;  // where the diagonal meets the top edge
    const ty = 200;  // first title baseline: top-left, ~110 px margin like the left edge
    const lines = mod.titleLines || wrap(mod.name, e, TITLE.x, ty, TITLE.lead, TITLE.ch);
    const tagY = ty + (lines.length - 1) * TITLE.lead + TAG.gap;
    const tag = splitTagline(mod.tagline, room(e, TAG.x, tagY, TAG.ch));
    const gx = o.text ? 1230 : 1060;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1080" width="1920" height="1080" style="${vars}">
      <defs>${DEFS}</defs><style>${SVG_CSS}</style>
      <rect width="1920" height="1080" fill="${DARK}"/>
      ${mod.fieldFrom ? `<defs><linearGradient id="sqField" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${mod.fieldFrom}"/><stop offset="1" stop-color="${field}"/></linearGradient></defs>` : ''}
      <path d="M0 0 H${e} L${e - 1080} 1080 H0 Z" fill="${mod.fieldFrom ? 'url(#sqField)' : field}"/>
      <path d="M0 0 H${e} L${e - 1080} 1080 H0 Z" fill="url(#sqSheen)"/>
      <path d="M${e + 70} 0 L${e - 1010} 1080" stroke="${field}" stroke-width="16"/>
      ${glyph(mod, gx, 230, 640)}
      ${mod.overlay ? mod.overlay(Square, { ...o, dx: gx - 1230 }) : ''}
      ${mod.deprecated ? sash(mod.deprecated) : ''}
      ${o.text ? `
        <text class="t" font-weight="800" font-size="${TITLE.size}" fill="${INK_ON_BRAND}">${lines.map((l, i) => `<tspan x="${TITLE.x}" y="${ty + i * TITLE.lead}">${esc(l)}</tspan>`).join('')}</text>
        <text class="t" font-size="${TAG.size}" font-weight="600" fill="${INK_ON_BRAND}" fill-opacity=".75">${tag.map((l, i) => `<tspan x="${TAG.x}" y="${tagY + i * TAG.lead}">${esc(l)}</tspan>`).join('')}</text>` : ''}
    </svg>`;
  }

  // ---------- State series (US State Names): street sign + flag sticker ----------
  // Every state cover is identical except the title's first line and the flag file. The rules are in
  // branding/README.md "State series"; change them here, never per state.
  const STICKER = {
    cx: 1440, cy: 690,   // centre on the cover (text on): big enough to overtake the card, runs off the right and bottom edges
    w: 1000,             // flag width; height = w / aspect
    border: 22,          // white die-cut margin around the flag
    r: 26,               // outer corner radius (inner = r - border / 2)
    angle: -7,           // tilt in degrees (negative = counter-clockwise)
    peel: 120,           // size of the peeled bottom-right corner (along each edge of the outer shape)
  };
  // The street-name sign behind the sticker: a post with a blank blade, two knocked-out bars.
  const streetSign = () => `
    <rect class="ink" x="470" y="100" width="56" height="790" rx="16"/>
    <rect class="ink sep" x="230" y="-30" width="535" height="170" rx="30"/>
    <rect class="cut" x="285" y="25" width="290" height="28" rx="14"/>
    <rect class="cut" x="285" y="73" width="190" height="28" rx="14"/>
    <rect class="ink" x="383" y="870" width="230" height="40" rx="20"/>`;
  function sticker(mod, dx) {
    const k = mod.id, s = STICKER, w = s.w, h = Math.round(w / mod.flagAspect);
    const W = w + 2 * s.border, H = h + 2 * s.border, X = W / 2, Y = H / 2, R = s.r, p = s.peel;
    // Outer die-cut shape, centred on 0,0, bottom-right corner cut off along the fold line.
    const outer = `M${-X + R} ${-Y} H${X - R} A${R} ${R} 0 0 1 ${X} ${-Y + R} V${Y - p} L${X - p} ${Y} H${-X + R}
      A${R} ${R} 0 0 1 ${-X} ${Y - R} V${-Y + R} A${R} ${R} 0 0 1 ${-X + R} ${-Y} Z`;
    // The folded-back corner: the cut-off triangle mirrored over the fold line, its tip curling up a little.
    const fold = `M${X} ${Y - p} L${X - p} ${Y} Q${X - p * 0.98} ${Y - p * 0.55} ${X - p * 0.86} ${Y - p * 0.86}
      Q${X - p * 0.55} ${Y - p * 0.98} ${X} ${Y - p} Z`;
    const ir = R - s.border / 2;
    return `
      <defs>
        <filter id="stShadow_${k}" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="16" stdDeviation="22" flood-color="#000" flood-opacity=".45"/></filter>
        <filter id="stFoldShadow_${k}" x="-50%" y="-50%" width="200%" height="200%"><feDropShadow dx="-6" dy="-4" stdDeviation="7" flood-color="#000" flood-opacity=".35"/></filter>
        <clipPath id="stCut_${k}"><path d="${outer}"/></clipPath>
        <linearGradient id="stFoldGrad_${k}" x1="1" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#9aa5b0"/><stop offset=".5" stop-color="#d9dfe5"/><stop offset="1" stop-color="#f7f9fa"/></linearGradient>
        <linearGradient id="stGloss_${k}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".4" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".08"/></linearGradient>
      </defs>
      <g transform="translate(${s.cx + dx} ${s.cy})">
        <g filter="url(#stShadow_${k})"><path d="${outer}" fill="#fff" transform="rotate(${s.angle})"/></g>
        <g transform="rotate(${s.angle})">
          <g clip-path="url(#stCut_${k})">
            <svg x="${-w / 2}" y="${-h / 2}" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" overflow="hidden">
              <rect width="${w}" height="${h}" rx="${ir}" fill="#fff"/>
              <image href="flags/${mod.flag}" width="${w}" height="${h}" preserveAspectRatio="none" clip-path="inset(0 round ${ir}px)"/>
            </svg>
            <path d="${outer}" fill="url(#stGloss_${k})"/>
          </g>
          <path d="${fold}" fill="url(#stFoldGrad_${k})" filter="url(#stFoldShadow_${k})"/>
        </g>
      </g>`;
  }
  // One call per state in mods.js. `id: '…'` must stay at the start of a line there (render_covers.py greps it).
  //   id, state ("Washington"), flag ("us_washington.svg" in branding/flags/), flagAspect (SOURCES.json aspect),
  //   accent (the flag's main colour; README palette table only, the pictogram stays ink).
  function stateCover({ id, state, flag, flagAspect, accent }) {
    Square.register({
      id, name: `${state} Towns & Streets`, titleLines: [state, 'Towns & Streets'],
      tagline: 'Real towns, streets & stations', accent, flag, flagAspect, series: 'state',
      glyph: streetSign,
      overlay: (S, o) => sticker({ id, flag, flagAspect }, o.dx),
    });
  }

  // ---------- Local forks (SQ Opt) ----------
  // One call per fork in mods.js (`id: '…'` at the start of a line). The pictogram is a generic fork: one
  // branch splits off the main line, next to an accent lightning bolt (optimized). Pass glyph to override it.
  const forkGlyph = () => `
    <rect class="ink" x="222" y="130" width="56" height="560" rx="28"/>
    <path class="sink" d="M250 560 C 250 400, 540 420, 540 220" stroke-width="56" stroke-linecap="round"/>
    <circle class="ink" cx="250" cy="130" r="62"/><circle class="ink" cx="250" cy="690" r="62"/>
    <circle class="ink" cx="540" cy="190" r="62"/>
    <path class="acc" d="M610 430 L470 640 H560 L515 800 L690 560 H595 L660 430 Z"/>`;
  function forkCover({ id, name, tagline = 'Local copy, not for upload', accent = FORK, glyph = forkGlyph }) {
    Square.register({ id, name, tagline, accent, glyph, field: FORK, series: 'fork' });
  }

  // ---------- DEV mods (test harnesses, probes) ----------
  // One call per DEV mod in mods.js (`id: '…'` at the start of a line). The pictogram is a generic lab flask
  // with accent liquid and two rising bubbles. Pass glyph to override it, tagline for a specific line.
  const devGlyph = () => `
    <path class="ink" d="M300 110 H500 V320 L680 640 Q712 700 650 700 H150 Q88 700 120 640 L300 320 Z"/>
    <rect class="ink" x="250" y="70" width="300" height="70" rx="35"/>
    <path class="cut" d="M352 190 H448 V334 L515 455 H285 L352 334 Z"/>
    <path class="acc" d="M262 495 H538 L612 627 Q624 650 598 650 H202 Q176 650 188 627 Z"/>
    <circle class="cut" cx="345" cy="580" r="26"/><circle class="cut" cx="440" cy="545" r="18"/>`;
  function devCover({ id, name, group, tagline = 'Dev tool, not for upload', accent, glyph = devGlyph, titleLines }) {
    if (group && !DEV_GROUPS[group]) throw new Error(`devCover ${id}: unknown group '${group}'`);
    const g = group && DEV_GROUPS[group];
    const field = g ? g.to : DEV;
    Square.register({ id, name, tagline, accent: accent || field, glyph, titleLines, field, fieldFrom: g && g.from,
                     series: 'dev', group });
  }

  const Square = { BRAND, FORK, DEV, DEPRECATED, DEV_GROUPS, DARK, INK_ON_BRAND, LINE_COLORS, MODS: [], STICKER,
                   factory, ground, arrowHead, render, stateCover, forkCover, devCover, streetSign, defs: DEFS, css: SVG_CSS,
                   register(mod) { Square.MODS.push(mod); } };
  window.Square = Square;
})();
