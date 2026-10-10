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
    .mod { font-weight: 800; font-size: 32px; opacity: .55; margin-bottom: 26px; }
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
    .table td:last-child { font-weight: 800; }`;

  const fit = (w, h, bw, bh) => Math.min(bw / w, bh / h);

  // One cropped capture at scale s, top-left at (x, y). m = { src, crop: [x, y, w, h] } in capture pixels.
  function crop(m, s, x, y, extra = '') {
    const [cx, cy, cw, ch] = m.crop;
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
    // Two crops of the same UI stacked, each labelled (e.g. game default vs with the mod).
    stack(md) {
      const [, , w, h] = md.items[0].crop, lab = 62, gap = 56;
      const s = fit(w, h, BOX.w, (BOX.h - 2 * lab - gap) / 2);
      const x = BOX.x + (BOX.w - w * s) / 2;
      let y = BOX.y + (BOX.h - 2 * (lab + h * s) - gap) / 2, out = '';
      md.items.forEach((it, i) => {
        out += chip(md.labels[i], i ? 'after' : 'before', x, y) + crop(it, s, x, y + lab);
        y += lab + h * s + gap;
      });
      return out;
    },
    // A text table card (no capture), vertically centred in the box: head = [col1, col2], rows = [[a, b], ...].
    table(md) {
      const row = cells => `<tr>${cells.map(c => `<td>${esc(c)}</td>`).join('')}</tr>`;
      return `<div class="table" style="left:${BOX.x + 40}px;top:50%;transform:translateY(-50%);width:${BOX.w - 40}px">
        <table><tr>${md.head.map(c => `<th>${esc(c)}</th>`).join('')}</tr>${md.rows.map(row).join('')}</table></div>`;
    },
  };

  function renderSlide(mod, slide) {
    const md = slide.media;
    return `<div class="slide">
      <div class="panel"></div>
      <svg style="position:absolute;left:0;top:0" width="${W}" height="${H}">
        <line x1="${EDGE_TOP + 60}" y1="0" x2="${EDGE_BOTTOM + 60}" y2="${H}" stroke="${S.BRAND}" stroke-width="16"/></svg>
      ${LAYOUTS[md.layout || 'single'](md)}
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
      return { ...sl, media: { ...abs(md), main: abs(md.main), inset: abs(md.inset), items: md.items && md.items.map(abs) } };
    });
  };
  S.renderSlide = renderSlide;
  S.slideCss = CSS;
})();
