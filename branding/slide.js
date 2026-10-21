// "square" house style for mod gallery slides (_metadata/1-<hash>.png, 2-<hash>.png, ...).
// Plain browser script, loaded after cover.js (palette) by slide.html and shots.html.
// A slide is 1920x1080 HTML: teal headline panel on the left, a cropped game capture on the
// dark field on the right. Per-mod slide data lives in shots.js; captures in plans/<id>/shots/.
(function () {
  const S = window.Square;
  const W = 1920, H = 1080;
  const EDGE_TOP = 720, EDGE_BOTTOM = 600;    // slanted right edge of the teal panel
  const BOX = { x: 800, y: 60, w: 1060, h: 960 };  // area the media is fitted into
  const SRC_W = 5120;                          // capture width (Retina 5K full-screen)

  const CSS = `
    .slide { position: relative; width: ${W}px; height: ${H}px; overflow: hidden; background: ${S.DARK};
             font-family: Overpass, 'Helvetica Neue', Arial, sans-serif; }
    .panel { position: absolute; inset: 0; background: ${S.BRAND};
             clip-path: polygon(0 0, ${EDGE_TOP}px 0, ${EDGE_BOTTOM}px 100%, 0 100%); }
    .panel::after { content: ''; position: absolute; inset: 0;
             background: linear-gradient(135deg, rgba(255,255,255,.14), rgba(255,255,255,0) 55%, rgba(0,0,0,.18)); }
    .text { position: absolute; left: 96px; top: 0; bottom: 0; width: 470px; display: flex;
            flex-direction: column; justify-content: center; color: ${S.INK_ON_BRAND}; }
    .mod { font-weight: 800; font-size: 32px; opacity: .55; margin-bottom: 26px; white-space: nowrap; }  /* one line, may run past .text into the panel */
    .bar { width: 84px; height: 12px; border-radius: 6px; background: ${S.INK_ON_BRAND}; margin-bottom: 34px; }
    .title { font-weight: 800; font-size: 80px; line-height: 86px; letter-spacing: -1px; }
    .sub { font-weight: 600; font-size: 40px; line-height: 50px; opacity: .75; margin-top: 30px; }
    .crop { position: absolute; overflow: hidden; border-radius: 18px;
            box-shadow: 0 24px 70px rgba(0,0,0,.55), 0 0 0 2px rgba(255,255,255,.07); }
    .crop img { position: absolute; display: block; max-width: none; }
    .wipe-line { position: absolute; pointer-events: none; }
    .chip { position: absolute; font-weight: 800; font-size: 30px; line-height: 1; padding: 14px 20px 10px;
            border-radius: 12px; white-space: nowrap; }
    .chip.before { background: rgba(24,32,42,.88); color: #eef2f6; }
    .chip.after { background: ${S.BRAND}; color: ${S.INK_ON_BRAND}; }
    .table { position: absolute; border-radius: 18px; overflow: hidden; background: #222c38; color: #eef2f6;
             box-shadow: 0 24px 70px rgba(0,0,0,.55), 0 0 0 2px rgba(255,255,255,.07); }
    .table table { width: 100%; border-collapse: collapse; }
    .table th { background: ${S.BRAND}; color: ${S.INK_ON_BRAND}; font-weight: 800; font-size: 30px; text-align: left;
                padding: 26px 32px 20px; }
    .table td { font-size: 30px; line-height: 38px; padding: 22px 32px 18px; vertical-align: top;
                border-top: 2px solid rgba(255,255,255,.07); }
    .table td:first-child { font-weight: 600; opacity: .8; width: 52%; }
    .table td:last-child { font-weight: 800; }
    .pcard { position: absolute; }
    .pcard.print > .crop { border: 10px solid #eef2f6; border-radius: 10px; box-sizing: content-box; }
    .pcard .chip { font-size: 24px; padding: 11px 16px 8px; border-radius: 10px; }
    .badge { position: absolute; box-sizing: border-box; border-radius: 16px; background: #222c38; color: #eef2f6; padding: 22px 26px 18px;
             box-shadow: 0 24px 70px rgba(0,0,0,.55), 0 0 0 2px rgba(255,255,255,.07); }
    .badge b { display: block; font-weight: 800; font-size: 42px; line-height: 1; color: ${S.BRAND}; letter-spacing: -1px; white-space: nowrap; }
    .badge span { display: block; font-weight: 600; font-size: 22px; line-height: 28px; opacity: .85; margin-top: 10px; white-space: nowrap; }`;

  const fit = (w, h, bw, bh) => Math.min(bw / w, bh / h);

  // One cropped capture at scale s, top-left at (x, y). m = { src, crop: [x, y, w, h] } in capture pixels.
  // fade (optional): [top, bottom] fractions of the crop height that fade out (a tall window shown in context);
  // the faded crop has no frame shadow or rounded corners.
  function crop(m, s, x, y, extra = '') {
    const [cx, cy, cw, ch] = m.crop;
    if (m.fade) {
      const [t, b] = m.fade.map(f => f * 100);
      const g = `linear-gradient(to bottom, transparent 0, #000 ${t}%, #000 ${100 - b}%, transparent 100%)`;
      extra += `-webkit-mask-image:${g};mask-image:${g};box-shadow:none;border-radius:0;`;
    }
    return `<div class="crop" style="left:${x}px;top:${y}px;width:${cw * s}px;height:${ch * s}px;${extra}">
      <img src="${m.src}" style="width:${(m.srcW || SRC_W) * s}px;left:${-cx * s}px;top:${-cy * s}px"></div>`;
  }
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const chip = (text, kind, x, y) => `<div class="chip ${kind}" style="left:${x}px;top:${y}px">${text}</div>`;

  // Media layouts. Each returns HTML positioned inside the 1920x1080 slide.
  const LAYOUTS = {
    // A single crop, centred in the box.
    single(md) {
      const [, , w, h] = md.crop, s = fit(w, h, BOX.w, BOX.h);
      return crop(md, s, BOX.x + (BOX.w - w * s) / 2, BOX.y + (BOX.h - h * s) / 2);
    },
    // A main crop with a smaller one overlapping a corner (at: tl | tr | bl | br).
    inset(md) {
      const [, , w, h] = md.main.crop, s = fit(w, h, BOX.w - 40, BOX.h - 40);
      const mx = BOX.x + 40 + (BOX.w - 40 - w * s) / 2, my = BOX.y + 20 + (BOX.h - 40 - h * s) / 2;
      const [, , iw, ih] = md.inset.crop, is = md.insetW / iw;
      const at = md.at || 'bl', o = 44;
      const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
      const ix = clamp(at[1] === 'l' ? mx - o : mx + w * s - iw * is + o, BOX.x - 40, W - 40 - iw * is);
      // insetY (optional): centre the inset at this fraction of the slide height instead of the corner.
      const iy = clamp(md.insetY != null ? H * md.insetY - ih * is / 2 : at[0] === 't' ? my - o : my + h * s - ih * is + o,
        40, H - 40 - ih * is);
      return crop(md.main, s, mx, my) + crop(md.inset, is, ix, iy);
    },
    // Same camera, two states: "before" fills the top-left of a 45° diagonal, "after" the rest.
    wipe(md) {
      const [, , w, h] = md.crop, s = fit(w, h, BOX.w, BOX.h);
      const x = BOX.x + (BOX.w - w * s) / 2, y = BOX.y + (BOX.h - h * s) / 2, pw = w * s, ph = h * s;
      const c = (md.split ?? 0.5) * (pw + ph);  // points with x + y < c show "before"
      const poly = `polygon(0 0, ${c}px 0, ${c - ph}px 100%, 0 100%)`;
      // beforeCrop (optional): a differently framed crop of "before", scaled to the same box, when the camera moved.
      const bc = md.beforeCrop || md.crop, bs = pw / bc[2];
      return crop({ ...md, src: md.after }, s, x, y)
        + crop({ ...md, src: md.before, crop: bc }, bs, x, y, `clip-path:${poly};box-shadow:none;height:${ph}px`)
        + `<div class="wipe-line" style="left:${x}px;top:${y}px;width:${pw}px;height:${ph}px;overflow:hidden;border-radius:18px">
             <svg width="${pw}" height="${ph}" style="position:absolute">
               <line x1="${c}" y1="0" x2="${c - ph}" y2="${ph}" stroke="${S.BRAND}" stroke-width="10"/></svg>
             <div class="chip before" style="left:24px;top:24px">${md.labels[0]}</div>
             <div class="chip ${md.darkChips ? 'before' : 'after'}" style="right:24px;bottom:24px">${md.labels[1]}</div></div>`;
    },
    // Crops of the same UI stacked, each labelled (e.g. game default vs with the mod, or one per vehicle type).
    // Items share a width and one scale; heights may differ. gap (optional) between items, default 56. The first
    // chip is dark and the others teal; chips: 'after' (optional) makes them all teal.
    stack(md) {
      const n = md.items.length, w = md.items[0].crop[2], lab = 62, gap = md.gap ?? 56;
      const sumH = md.items.reduce((a, it) => a + it.crop[3], 0);
      const s = fit(w, sumH, BOX.w, BOX.h - n * lab - (n - 1) * gap);
      const x = BOX.x + (BOX.w - w * s) / 2;
      let y = BOX.y + (BOX.h - (n * lab + sumH * s + (n - 1) * gap)) / 2, out = '';
      md.items.forEach((it, i) => {
        out += chip(md.labels[i], i || md.chips === 'after' ? 'after' : 'before', x, y) + crop(it, s, x, y + lab);
        y += lab + it.crop[3] * s + gap;
      });
      return out;
    },
    // Free placement, for a pile of captures (e.g. many test setups at once). items: [{ src, crop, x, y, w, rot,
    // label }]: x, y = the card's centre in slide pixels, w = its width, rot = degrees; drawn in order, last on
    // top. label (optional) puts a chip in the card's top-left corner. print: true gives every card a white
    // photo border. Badges (any layout, see renderSlide) carry the numbers.
    collage(md) {
      return md.items.map(it => {
        const [, , cw, ch] = it.crop, s = it.w / cw, h = ch * s;
        return `<div class="pcard${md.print ? ' print' : ''}" style="left:${it.x - it.w / 2}px;top:${it.y - h / 2}px;width:${it.w}px;height:${h}px;transform:rotate(${it.rot || 0}deg)">
          ${crop(it, s, 0, 0)}${it.label ? chip(esc(it.label), it.dark ? 'before' : 'after', 18, 18) : ''}</div>`;
      }).join('');
    },
    // A text table card (no capture), vertically centred in the box: head = [col1, col2], rows = [[a, b], ...].
    // top (optional): its top edge in slide pixels instead of centring. col1 (optional): the first column's width
    // in % (default 52, the stylesheet's), for a table whose second column holds the long entries.
    table(md) {
      const w1 = md.col1 != null ? ` style="width:${md.col1}%"` : '';
      const row = cells => `<tr>${cells.map((c, i) => `<td${i === 0 ? w1 : ''}>${esc(c)}</td>`).join('')}</tr>`;
      const pos = md.top != null ? `top:${md.top}px` : 'top:50%;transform:translateY(-50%)';
      return `<div class="table" style="left:${BOX.x + 40}px;${pos};width:${BOX.w - 40}px">
        <table><tr>${md.head.map(c => `<th>${esc(c)}</th>`).join('')}</tr>${md.rows.map(row).join('')}</table></div>`;
    },
  };

  function renderSlide(mod, slide) {
    // A mod's own slide style (style: 'postcard', postcard.js) replaces the teal-panel layout.
    if (slide.style && S.SLIDE_STYLES && S.SLIDE_STYLES[slide.style]) return S.SLIDE_STYLES[slide.style](mod, slide);
    const md = slide.media;
    return `<div class="slide">
      <div class="panel"></div>
      <svg style="position:absolute;left:0;top:0" width="${W}" height="${H}">
        <line x1="${EDGE_TOP + 60}" y1="0" x2="${EDGE_BOTTOM + 60}" y2="${H}" stroke="${S.BRAND}" stroke-width="16"/></svg>
      ${LAYOUTS[md.layout || 'single'](md)}
      ${(md.badges || []).map(b => `<div class="badge" style="left:${b.x}px;top:${b.y}px;${b.w ? `width:${b.w}px` : ''}">
        <b>${esc(b.big)}</b><span>${esc(b.small).replace(/\n/g, '<br>')}</span></div>`).join('')}
      ${md.table ? LAYOUTS.table(md.table) : ''}
      <div class="text">
        <div class="mod">${mod.name}</div>
        <div class="bar"></div>
        <div class="title">${slide.title}</div>
        <div class="sub">${slide.sub}</div>
      </div>
    </div>`;
  }

  // shots.js calls Square.slides(modId, [...]). Capture paths are relative to plans/<modId>/shots/.
  S.SLIDES = {};
  S.slides = (id, list) => {
    const dir = `../plans/${id}/shots/`;
    const abs = m => m && ({ ...m, src: m.src && dir + m.src, before: m.before && dir + m.before, after: m.after && dir + m.after });
    S.SLIDES[id] = list.map(sl => {
      const md = sl.media;
      return { ...sl, media: { ...abs(md), main: abs(md.main), inset: abs(md.inset), items: md.items && md.items.map(abs),
        photos: md.photos && md.photos.map(abs), uis: md.uis && md.uis.map(abs) } };
    });
  };
  S.renderSlide = renderSlide;
  S.slideCss = CSS;
})();
