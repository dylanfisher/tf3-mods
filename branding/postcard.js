// "Postcard" slide style: a mod's own gallery look inside the square family (first user: Photo Mode).
// Plain browser script, loaded after cover.js and slide.js. A slide whose entry in shots.js has style: 'postcard'
// is drawn here instead of the teal-panel layout: big, slightly tilted postcards (warm paper border, a handwritten
// caption, a square stamp and a postmark) over a blurred, darkened copy of the main photo, a teal note card with
// the title and sub line, and smaller taped UI cards showing the window that made the picture.
//
// media: {
//   photos: [{ src, x, y, w, rot, caption, crop?, srcW?, stamp?, postmark? }]  postcards, last on top;
//           x, y = centre of the card in slide pixels, w = photo width, crop = [x, y, w, h] in source pixels
//           (default: the whole 16:9 image), srcW = source width (default 2560), capLeft = caption on the left
//   uis:    [{ src, crop, srcW, x, y, w, rot, tape? }]  taped UI cards (crop in source pixels)
//   note:   { x, y, w, rot }  the teal title note (top-left corner, width)
//   bg:     index into photos for the blurred background (default 0)
// }
// Square.postcardCss holds the CSS; Square.renderPostcard(mod, slide, size) draws one slide (size = [w, h],
// default 1920x1080; the poster uses its own size).
(function () {
  const S = window.Square;
  const PAPER = '#f3eee4', PEN = '#26313d';
  const SRC_W = 2560, SRC_H = 1440;

  const CSS = `
    .pc-slide { position: relative; overflow: hidden; background: ${S.DARK};
                font-family: Overpass, 'Helvetica Neue', Arial, sans-serif; }
    .pc-bg { position: absolute; inset: -60px; background-size: cover; background-position: center;
             filter: blur(26px) saturate(1.15) brightness(.42); }
    .pc-vig { position: absolute; inset: 0;
              background: radial-gradient(ellipse at 60% 45%, rgba(0,0,0,0) 35%, rgba(8,12,18,.65) 100%); }
    .pc-card { position: absolute; background: ${PAPER}; padding: 20px 20px 0; border-radius: 4px; overflow: hidden;
               box-shadow: 0 30px 80px rgba(0,0,0,.6), 0 4px 14px rgba(0,0,0,.35); }
    .pc-card::after { content: ''; position: absolute; inset: 0; border-radius: 4px; pointer-events: none;
               background: linear-gradient(160deg, rgba(255,255,255,.35), rgba(255,255,255,0) 40%, rgba(120,100,70,.08)); }
    .pc-photo { position: relative; overflow: hidden; }
    .pc-photo img { position: absolute; display: block; max-width: none; }
    .pc-foot { position: relative; display: flex; align-items: center; justify-content: space-between; }
    .pc-cap { font-family: Caveat, 'Bradley Hand', cursive; font-weight: 600; color: ${PEN}; white-space: nowrap;
              transform: rotate(-1deg); }
    .pc-stamp { position: absolute; filter: drop-shadow(0 3px 6px rgba(0,0,0,.35)); }
    .pc-stamp > svg { position: absolute; inset: 0; }
    .pc-stamp-in { position: absolute; inset: 9px; background: ${S.BRAND}; display: flex; flex-direction: column;
                   align-items: center; justify-content: center; box-sizing: border-box;
                   color: ${S.INK_ON_BRAND}; font-weight: 800; }
    .pc-post { position: absolute; pointer-events: none; mix-blend-mode: multiply; opacity: .8; }
    .pc-note { position: absolute; background: ${S.BRAND}; color: ${S.INK_ON_BRAND}; border-radius: 6px;
               padding: 54px 46px 46px; box-shadow: 0 26px 60px rgba(0,0,0,.55); }
    .pc-note::before { content: ''; position: absolute; inset: 0; border-radius: 6px;
               background: linear-gradient(135deg, rgba(255,255,255,.16), rgba(255,255,255,0) 55%, rgba(0,0,0,.14)); }
    .pc-note .m { position: relative; font-weight: 800; font-size: 28px; opacity: .6; margin-bottom: 18px; }
    .pc-note .b { position: relative; width: 72px; height: 10px; border-radius: 5px; background: ${S.INK_ON_BRAND};
                  margin-bottom: 26px; }
    .pc-note .t { position: relative; font-weight: 800; font-size: 66px; line-height: 70px; letter-spacing: -1px; }
    .pc-note .s { position: relative; font-weight: 600; font-size: 31px; line-height: 40px; opacity: .78; margin-top: 22px; }
    .pc-tape { position: absolute; height: 46px; background: rgba(236,229,210,.72);
               box-shadow: 0 2px 6px rgba(0,0,0,.18); }
    .pc-ui { position: absolute; background: ${PAPER}; padding: 10px; border-radius: 6px;
             box-shadow: 0 26px 60px rgba(0,0,0,.6), 0 3px 10px rgba(0,0,0,.3); }
    .pc-ui .pc-photo { border-radius: 4px; }`;

  let uid = 0;
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

  // The cropped image filling a box of width w (height follows the crop's aspect).
  function img(src, crop, srcW, w) {
    const [cx, cy, cw, ch] = crop, s = w / cw;
    return { h: ch * s, html: `<div class="pc-photo" style="width:${w}px;height:${ch * s}px">
      <img src="${src}" style="width:${srcW * s}px;left:${-cx * s}px;top:${-cy * s}px"></div>` };
  }

  const tape = (x, y, w, rot) =>
    `<div class="pc-tape" style="left:${x}px;top:${y}px;width:${w}px;transform:rotate(${rot}deg)"></div>`;

  // Stamp: a perforated paper square with a teal camera (the cover's camera, simplified) and the mod name.
  function stamp(size) {
    const w = size, h = Math.round(size * 1.2), r = 4.5, step = 13;
    const holes = [];
    for (let x = step / 2; x < w; x += step) holes.push([x, 0], [x, h]);
    for (let y = step / 2; y < h; y += step) holes.push([0, y], [w, y]);
    const id = 'st' + uid++;
    return { w, h, html: `<svg width="${w}" height="${h}"><defs><mask id="${id}"><rect width="${w}" height="${h}" fill="#fff"/>
        ${holes.map(([x, y]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="#000"/>`).join('')}</mask></defs>
        <rect width="${w}" height="${h}" fill="${PAPER}" mask="url(#${id})"/></svg>
      <div class="pc-stamp-in">
      <svg viewBox="0 0 100 80" width="${w * .62}" height="${w * .5}">
        <path d="M33 18 L39 8 H61 L67 18 Z" fill="${S.INK_ON_BRAND}"/>
        <rect x="6" y="16" width="88" height="58" rx="10" fill="${S.INK_ON_BRAND}"/>
        <circle cx="50" cy="45" r="21" fill="${S.BRAND}"/><circle cx="50" cy="45" r="13" fill="#8FD3FF"/>
        <circle cx="50" cy="45" r="6" fill="${S.INK_ON_BRAND}"/><rect x="76" y="23" width="10" height="6" rx="2" fill="${S.BRAND}"/>
      </svg>
      </div>` };
  }

  // Postmark: a double ring with curved text and wavy cancel lines to its right.
  function postmark(d, text, id) {
    const r = d / 2, waves = [0, 1, 2, 3].map(i => {
      const y = r - d * .2 + i * d * .13;
      let p = `M${d - 6} ${y}`;
      for (let k = 0; k < 2; k++) p += ` q${22} ${-9} ${44} 0 t${44} 0`.replace(/^ /, ' ');
      return `<path d="${p}" fill="none" stroke="${PEN}" stroke-width="4" stroke-linecap="round"/>`;
    }).join('');
    return `<svg width="${d + 200}" height="${d}" viewBox="0 0 ${d + 200} ${d}">
      <defs><path id="${id}" d="M ${r} ${r} m -${r - 26} 0 a ${r - 26} ${r - 26} 0 1 1 ${2 * (r - 26)} 0 a ${r - 26} ${r - 26} 0 1 1 -${2 * (r - 26)} 0"/></defs>
      <circle cx="${r}" cy="${r}" r="${r - 4}" fill="none" stroke="${PEN}" stroke-width="5"/>
      <circle cx="${r}" cy="${r}" r="${r - 46}" fill="none" stroke="${PEN}" stroke-width="3"/>
      <text font-family="Overpass Mono, monospace" font-weight="700" font-size="${d * .1}" fill="${PEN}" letter-spacing="3">
        <textPath href="#${id}">${esc(text)}</textPath></text>
      <text x="${r}" y="${r + d * .06}" text-anchor="middle" font-family="Overpass, sans-serif" font-weight="800"
            font-size="${d * .17}" fill="${PEN}">TF3</text>
      ${waves}</svg>`;
  }

  function postcard(p, mod) {
    const crop = p.crop || [0, 0, p.srcW || SRC_W, (p.srcW || SRC_W) * SRC_H / SRC_W];
    const ph = img(p.src, crop, p.srcW || SRC_W, p.w);
    const pad = 20, foot = Math.round(p.w * .062);
    const cw = p.w + 2 * pad, ch = ph.h + pad + foot;
    const capSize = Math.round(foot * .62);
    let extra = '';
    if (p.stamp !== false) {
      const st = stamp(Math.round(p.w * .09));
      extra += `<div class="pc-stamp" style="right:${pad + p.w * .025}px;top:${pad + p.w * .025}px;width:${st.w}px;height:${st.h}px;transform:rotate(3deg)">${st.html}</div>`;
      if (p.postmark !== false) {
        const d = Math.round(p.w * .15);
        extra += `<div class="pc-post" style="right:${pad + p.w * .025 + st.w * .78}px;top:${pad + p.w * .025 + st.h * .38}px;width:${d}px;height:${d}px;transform:rotate(-12deg);transform-origin:${d / 2}px ${d / 2}px">
          <div style="position:absolute;left:0;top:0">${postmark(d, p.postmark || 'SQUARE · PHOTO MODE · 2026 ·', 'pm' + uid++)}</div></div>`;
      }
    }
    return `<div class="pc-card" style="left:${p.x - cw / 2}px;top:${p.y - ch / 2}px;width:${cw}px;height:${ch}px;box-sizing:border-box;transform:rotate(${p.rot || 0}deg)">
      ${ph.html}
      <div class="pc-foot" style="height:${foot}px;justify-content:${p.capLeft ? 'flex-start' : 'flex-end'}">
        <div class="pc-cap" style="font-size:${capSize}px">${esc(p.caption || '')}</div>
      </div>${extra}</div>`;
  }

  function uiCard(u) {
    const ph = img(u.src, u.crop, u.srcW, u.w);
    const cw = u.w + 20, ch = ph.h + 20;
    return `<div class="pc-ui" style="left:${u.x - cw / 2}px;top:${u.y - ch / 2}px;width:${cw}px;height:${ch}px;box-sizing:border-box;transform:rotate(${u.rot || 0}deg)">
      ${ph.html}${u.tape === false ? '' : tape(cw / 2 - 70, -22, 140, -4)}</div>`;
  }

  function renderPostcard(mod, slide, size = [1920, 1080]) {
    const md = slide.media, [W, H] = size;
    const bg = md.photos[md.bg || 0];
    const n = md.note;
    const note = n ? `<div class="pc-note" style="left:${n.x}px;top:${n.y}px;width:${n.w}px;box-sizing:border-box;transform:rotate(${n.rot || 0}deg)">
        ${tape(n.w / 2 - 80, -24, 160, 3)}
        <div class="m">${esc(mod.shortName || mod.name)}</div><div class="b"></div>
        <div class="t">${slide.title}</div>${slide.sub ? `<div class="s">${slide.sub}</div>` : ''}</div>` : '';
    return `<div class="pc-slide" style="width:${W}px;height:${H}px">
      <div class="pc-bg" style="background-image:url('${bg.src}')"></div><div class="pc-vig"></div>
      ${md.photos.map(p => postcard(p, mod)).join('')}
      ${(md.uis || []).map(uiCard).join('')}
      ${note}${md.extra || ''}</div>`;
  }

  // Per-mod cover (render.html uses it instead of Square.render, so make covers writes it as _metadata/0.png):
  // the house cover (teal field, title, tagline; Square.render with the pictogram left out) with tilted postcards
  // on the dark side in place of the pictogram. 1920x1080, legible at mod.io's 320x180 thumbnail.
  S.COVERS = S.COVERS || {};
  S.COVERS.square_photo_mode = mod => {
    const dir = '../plans/square_photo_mode/shots/';
    const cards = [
      { src: dir + '05-neon-intersection.jpg', x: 1620, y: 295, w: 800, rot: 8, caption: 'Neon dusk', stamp: false },
      { src: dir + '01-deer-herd-rain.jpg', x: 1700, y: 800, w: 800, rot: -8, caption: 'Red deer, pink rain', stamp: false },
      { src: dir + '02-golden-town-market.jpg', x: 1300, y: 560, w: 800, rot: -3, caption: 'Golden hour' } ];
    return `<div style="position:relative;width:1920px;height:1080px;overflow:hidden">
      ${S.render({ ...mod, glyph: () => '' })}
      <div style="position:absolute;inset:0">${cards.map(p => postcard(p, mod)).join('')}</div></div>`;
  };

  S.postcardCss = CSS;
  S.renderPostcard = renderPostcard;
  S.SLIDE_STYLES = S.SLIDE_STYLES || {};
  S.SLIDE_STYLES.postcard = (mod, slide) => renderPostcard(mod, slide);
})();
