// Organic Towns Name lab (page logic). Data: data.js (export_names.py), ideas.js (lab word lists), gen.js (the JS port
// of ot_placename), port_check.js. No dependencies; works from file://.
(function () {
  'use strict';
  const D = window.NAMEDATA, IDEAS0 = window.NAMEIDEAS || {}, NG = window.NameGen;
  const { b, u, rng } = NG;
  const $ = (s, el) => (el || document).querySelector(s);
  const $$ = (s, el) => Array.from((el || document).querySelectorAll(s));
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const f2 = v => (v == null || isNaN(v)) ? '-' : (+v).toFixed(2);
  const KEY = 'ot-name-lab-v1';

  const MODES = [
    { id: 'morph', name: 'Morpheme', desc: 'The mod\'s generator (ot_placename): a stem and a generic picked by how well their tags fit the site, dialect, affix.' },
    { id: 'remix', name: 'Real-name remix', desc: 'A character Markov chain trained on the game\'s own town list for the language, optionally starting with a fitting stem or ending with a fitting generic.' },
    { id: 'desc', name: 'Descriptive', desc: 'Terrain words only: plain terrain / colour words and the terrain generics, no personal names, no affix ("Ashwater", "Fellside").' },
    { id: 'feat', name: 'Feature + settlement', desc: 'The river or lake\'s name with a settlement word ("Avonbury", "Lahnheim"); a stream name when the site has no water.' },
    { id: 'old', name: 'Old forms', desc: 'Old spellings of the morpheme names, and the inventory\'s Celtic / Norse forms (Aber-, Pen-, -by, -thwaite) pushed forward.' },
    { id: 'map', name: 'Whole map (plan)', desc: 'The mod\'s whole-map naming (ot_placename.assign): a map of towns of mixed sites, or an imported game log\'s sites, named with the per-map plan (shapes, settlement layers, twins, the feature budget, the climate\'s table). Rate the set, compare shapes, read the Q7 numbers.' },
  ];
  const MODE = {}; MODES.forEach(m => { MODE[m.id] = m; });
  const TOWNISH = { any: 1, market: 1, church: 1, big: 1, small: 1, character: 1, district: 1, works: 1, old: 1, new: 1 };
  const SETTLE = { any: 1, plain: 1, field: 1, meadow: 1, market: 1, church: 1, old: 1, big: 1, small: 1 };
  const GROUPS = [
    ['Rivers', ['river', 'mouth', 'ford', 'bridge', 'bend', 'confluence', 'spring', 'brook']],
    ['Lakes', ['lake', 'mere', 'pool', 'tarn']],
    ['Coast', ['coast', 'sandy', 'rocky', 'cliff', 'bay', 'headland', 'spit', 'island']],
    ['Hills', ['hill', 'hilltop', 'slope', 'ridge', 'pass', 'foot', 'mountain', 'rock']],
    ['Valleys', ['valley', 'vale', 'gorge', 'combe']],
    ['Wet ground, heath', ['marsh', 'fen', 'moor', 'heath']],
    ['Forest', ['forest', 'edge', 'clearing']],
    ['Trees', D.pn.SPECIES],
    ['Open land', ['plain', 'field', 'meadow']],
    ['Town', ['market', 'church', 'big', 'small', 'district', 'works', 'old', 'new']],
  ];
  const LANG_NAMES = { en: 'English (England)', usa: 'American English', de: 'German', fr: 'French', it: 'Italian', es: 'Spanish',
    pt: 'Portuguese', nl: 'Dutch', sv: 'Swedish', nb: 'Norwegian', ja: 'Japanese (kanji)', ja_r: 'Japanese (romaji)' };
  const baseLang = l => l === 'ja_r' ? 'ja' : l;

  // ------------------------------------------------------------------ state
  function defaults() {
    return { v: 1, lang: 'en', climate: 'temperate', mode: 'morph', view: 'grid', seed: 1, dialect: 'auto', affixP: 1, character: false, shared: true, budget: true,
      preset: 'lakeside', site: Object.assign({}, D.presets.lakeside), consts: {}, spec: {}, edits: {}, ideas: {},
      opt: { order: 3, bias: 0.5, singleWords: true, oldShare: 0.4, spelling: true, count: 50 },
      ratings: {}, pinned: {}, notes: '', tab: 'map', listKind: 'spec', listFilter: '', listSort: 'fit',
      // (NEXT_PHASE_BRIEF 53 Part B: map mode)
      mapPreset: 'valley', mapSrc: 'synthetic', mapYear: 1850, mapRatings: {}, ab: [], abI: 0, quotaEdit: {}, imported: null };
  }
  let S = defaults();
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) { const o = JSON.parse(raw); if (o && o.v === 1) S = Object.assign(defaults(), o, { opt: Object.assign(defaults().opt, o.opt || {}) }); }
  } catch (e) { /* storage blocked: defaults */ }
  // link parameters: #mode=remix|all&lang=de&tab=lists&preset=island&seed=7&theme=dark
  try {
    const h = new URLSearchParams(location.hash.slice(1));
    if (h.get('mode') === 'all') S.view = 'all'; else if (h.get('mode')) { S.view = 'grid'; S.mode = h.get('mode'); }
    if (h.get('lang')) S.lang = h.get('lang');
    if (h.get('tab')) S.tab = h.get('tab');
    if (h.get('seed')) S.seed = +h.get('seed') || 1;
    if (h.get('preset') && D.presets[h.get('preset')]) { S.preset = h.get('preset'); S.site = Object.assign({}, D.presets[S.preset]); }
    if (h.get('theme')) document.documentElement.setAttribute('data-theme', h.get('theme'));
  } catch (e) { /* ignore */ }
  if (!D.lang[baseLang(S.lang)]) S.lang = 'en';
  if (!MODE[S.mode]) S.mode = 'morph';
  let saveT = null;
  function save() {
    clearTimeout(saveT);
    saveT = setTimeout(() => { try { localStorage.setItem(KEY, JSON.stringify(S)); } catch (e) { /* ignore */ } }, 250);
  }

  // ------------------------------------------------------------------ engine
  let M = null, M0 = NG.create(D);
  function rebuild() { M = NG.create(D, { consts: S.consts, spec: S.spec, edits: S.edits }); }
  rebuild();
  const realCache = {};
  function realSet(lang) {
    if (!realCache[lang]) {
      const r = {};
      for (const n of ((D.towns[lang] || {}).names || [])) r[M0.lowerAll(b(n))] = true;
      realCache[lang] = r;
    }
    return realCache[lang];
  }
  function ideas(lang) {
    const bl = baseLang(lang);
    return Object.assign({ adj: '', old: '', oldGroups: '' }, IDEAS0[bl] || {}, (S.ideas || {})[bl] || {});
  }
  function siteW() {
    const w = {};
    for (const k in S.site) if (S.site[k] >= 0.2) w[k] = S.site[k];
    if (S.character) { w.character = 1; w.church = Math.max(w.church || 0, 0.4); }
    return w;
  }
  const hasRiver = w => w.river != null;
  const hasLake = w => w.lake != null || w.pool != null || w.mere != null || w.tarn != null;
  function dialectObj(L) {
    if (S.dialect === 'auto' || S.dialect === 'none') return null;
    // (NEXT_PHASE_BRIEF 53: a dialect area's weights, its own group first)
    return M.areaObj(L, b(S.dialect));
  }
  function mulberry(a) {
    return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  }

  // A run of n towns with the same site. hook(ctx, q, i) -> [name, info] (null: nameTown with q). Returns results.
  function runTowns(n, opts) {
    const L = M.lang(S.lang);
    const w = siteW();
    // (the map's climate, ot_climate: its site tags in, the tags it never takes out, as siteTags does)
    const clim = S.climate || 'temperate';
    const site = (M.CL.SITE || {})[clim] || {};
    for (const k in site) if ((w[k] || 0) < site[k]) w[k] = site[k];
    for (const k in w) if (M.vetoTag(clim, k)) delete w[k];
    const out = [];
    const shared = opts.shared != null ? opts.shared : S.shared;
    let ctx = null;
    // shared: one map, every town in one context; alone: each town on its own map (seed + i)
    const fresh = i => {
      const c = M.newCtx(S.lang, shared ? S.seed : S.seed + i - 1, realSet(S.lang));
      c.climate = S.climate || 'temperate';
      if (S.dialect === 'auto') {
        const towns = [];
        for (let i = 1; i <= n; i++) towns.push({ x: ((i - 1) % 7) * 6000, y: Math.floor((i - 1) / 7) * 6000 });
        M.regions(c, towns);
      }
      // (the map's word budget, ot_namewords: a generic word at most once per 8 towns of the run; the towns stand 6 km
      // apart, so the 5 km neighbour rule doesn't bite here)
      if (shared && S.budget !== false) c.budget = M.NW.newBudget(M.CLS_OF_GEN[S.lang] || S.lang, n);
      return c;
    };
    const rivers = {}, lakes = {};
    for (let i = 1; i <= n; i++) {
      if (!ctx || !shared) ctx = fresh(i);
      const id = 1000 + i;
      const q = { id, x: ((i - 1) % 7) * 6000, y: Math.floor((i - 1) / 7) * 6000, w, character: S.character };
      // the map survey's facts for the cue tags of the site: the compass side, the side of the big lake, the map's
      // mountain and bay (named once per context)
      let bd = null, bv = 0;
      for (const d of ['north', 'south', 'east', 'west']) if ((w[d] || 0) > bv) { bd = d; bv = w[d]; }
      if (bd) q.dir = bd;
      if ((w.biglake || 0) > 0) q.ldir = bd || 'west';
      if ((w.peak || 0) > 0 || (w.summit || 0) > 0 || (w.range || 0) > 0 || (w.divide || 0) > 0) {
        if (ctx.labMount === undefined) ctx.labMount = M.featName(ctx, 'mount');
        q.mount = ctx.labMount;
      }
      if ((w.bigbay || 0) > 0) {
        if (ctx.labBay === undefined) ctx.labBay = M.featName(ctx, 'bay');
        q.bay = ctx.labBay;
      }
      const dia = dialectObj(L);
      if (dia) q.dialect = dia;
      const k = Math.floor((i - 1) / 5) + 1;
      if (hasRiver(w)) {
        if (!rivers[k] || !shared) rivers[k] = M.riverName(ctx, k);
        if (rivers[k]) { q.river = rivers[k]; q.specs = [M.riverEntry(ctx, rivers[k])]; }
      }
      if (hasLake(w)) {
        if (!lakes[k] || !shared) lakes[k] = M.lakeName(ctx, k);
        if (lakes[k]) q.lake = lakes[k];
      }
      if (S.affixP < 1 && rng.unit(S.seed, 'labAffix', id) >= S.affixP) q.noAffix = true;
      const r = opts.hook(ctx, q, i, L);
      if (r) out.push(r);
    }
    return out;
  }
  function partsOf(info) {
    if (!info) return [];
    return [u(info.spec), u(info.gen), info.affix ? u(info.affix) : null].filter(Boolean);
  }
  function morphResult(mode, ctx, q, L, extra) {
    const [nm, info] = M.nameTown(ctx, q);
    if (!nm) return { mode, name: null, fail: info };
    const r = { mode, name: u(nm), parts: partsOf(info), info, river: q.river ? u(q.river.n) : null, lake: q.lake ? u(q.lake.n) : null };
    return Object.assign(r, extra || {});
  }

  function genMorph(n) { return runTowns(n, { hook: (ctx, q, i, L) => morphResult('morph', ctx, q, L) }); }

  function descLists(L) {
    const specs = L.specs.filter(e => !e.flags.p && !e.flags.c && e.main && !TOWNISH[e.main] && (L.script || e.kind !== 'phrase'));
    for (const toks of M.lines(b(ideas(S.lang).adj))) specs.push(M.parseSpec(toks, false));
    const gens = L.gens.filter(e => !e.flags.p && !e.flags.c && !e.flags.t && e.main && !TOWNISH[e.main]);
    return [specs, gens];
  }
  function genDesc(n) {
    return runTowns(n, { hook: (ctx, q, i, L) => {
      const [specs, gens] = descLists(L);
      q.specList = specs; q.gens = gens; q.noAffix = true; q.specs = null; q.dialect = q.dialect || null;
      if (!q.dialect) q.dialect = { name: b('none'), w: {} };
      return morphResult('desc', ctx, q, L);
    } });
  }

  function featLists(ctx, L, w) {
    const feats = [];
    const water = hasRiver(w) || hasLake(w);
    if (hasLake(w)) {
      for (const stem of (L.data.lakes ? L.data.lakes.split('|') : [])) {
        const e = M.newEntry(stem); e.kind = 'stem'; M.parseTags([stem, 'lake', 'mere:.6', 'pool:.5'], 2, e); e.feature = 'lake'; feats.push(e);
      }
    }
    if (hasRiver(w) || !water || feats.length === 0) {
      const c2 = M.newCtx(S.lang, S.seed + 7, realSet(S.lang));
      for (let k = 1; k <= 12; k++) {
        const rv = M.riverName(c2, k);
        if (!rv) break;
        // the river's stem as join allows it (prefixes: "Villeloue") and as a plain stem ("Vila Mondego")
        for (const plain of [false, true]) {
          const e = M.riverEntry(ctx, rv);
          if (!water) { e.tl = [['brook', 1], ['river', 0.6]]; M.parseTags([], 2, e); }
          if (plain && !L.script) e.river = false;
          e.feature = water ? 'river' : 'stream';
          if (!plain || !L.script) feats.push(e);
        }
      }
    }
    const gens = L.gens.filter(e => !e.flags.p && !e.flags.c && (SETTLE[e.main] || e.tl.some(p => p[0] === 'any' && p[1] >= 0.3)));
    return [feats, gens];
  }
  function genFeat(n) {
    return runTowns(n, { hook: (ctx, q, i, L) => {
      const [feats, gens] = featLists(ctx, L, q.w);
      q.specList = feats; q.gens = gens; q.noAffix = true; q.specs = null;
      return morphResult('feat', ctx, q, L);
    } });
  }

  function oldRules(lang) {
    const out = [];
    for (const line of ideas(lang).old.split('\n')) {
      const t = line.trim();
      if (!t || t[0] === '#') continue;
      const i = t.indexOf('=>');
      if (i < 0) continue;
      const pat = line.slice(0, line.indexOf('=>')).trim(), rep = line.slice(line.indexOf('=>') + 2).replace(/^ /, '');
      try { out.push([new RegExp(pat, 'g'), rep, pat]); } catch (e) { /* bad regex: skipped */ }
    }
    return out;
  }
  function genOld(n) {
    const rules = S.opt.spelling ? oldRules(S.lang) : [];
    const groups = ideas(S.lang).oldGroups.split(/\s+/).filter(Boolean);
    return runTowns(n, { hook: (ctx, q, i, L) => {
      const pref = rng.unit(S.seed, 'labOld', q.id) < S.opt.oldShare;
      let how = 'spelling';
      if (pref && groups.length) {
        const g = L.gens.filter(e => e.grp && groups.indexOf(u(e.grp)) >= 0);
        if (g.length) { q.gens = g; q.dialect = { name: b('old'), w: {} }; how = 'old ' + groups.join(' / ') + ' forms'; }
      }
      const r = morphResult('old', ctx, q, L);
      if (!r.name) return r;
      // (each word on its own: "$" is a word's end, "Strathburn-in-the-Forest" -> "Strathburne-in-the-Forest")
      const applied = [];
      const nm = r.name.split(/([ \-]+)/).map((wd, wi) => {
        if (wi % 2 === 1 || wd === '') return wd;
        for (const [re, rep, pat] of rules) {
          re.lastIndex = 0;
          const nn = wd.replace(re, rep);
          if (nn !== wd) { if (applied.indexOf(pat + ' => ' + rep) < 0) applied.push(pat + ' => ' + rep); wd = nn; }
        }
        return wd;
      }).join('');
      r.modern = r.name; r.name = nm; r.applied = applied; r.how = how;
      return r;
    } });
  }

  // remix: back-off character Markov chain
  const chainCache = {};
  function chain(lang, order, single) {
    const key = lang + '|' + order + '|' + single;
    if (chainCache[key]) return chainCache[key];
    // (kanji: without the 市 / 町 / 村 the generator adds itself)
    let names = ((D.towns[lang] || {}).names || []).map(n => lang === 'ja' ? n.replace(/[市町村]$/, '') : n).filter(Boolean);
    if (single) names = names.filter(n => !/[ \-]/.test(n));
    const tbl = [];
    for (let o = 1; o <= order; o++) tbl[o] = {};
    for (const n of names) {
      const s = Array.from('\u0002'.repeat(order) + n + '\u0003');
      for (let i = order; i < s.length; i++) {
        for (let o = 1; o <= order; o++) {
          const ctxS = s.slice(i - o, i).join('');
          const m = tbl[o][ctxS] || (tbl[o][ctxS] = {});
          m[s[i]] = (m[s[i]] || 0) + 1;
        }
      }
    }
    return (chainCache[key] = { tbl, order, n: names.length, names });
  }
  function nextChar(C, hist, rnd) {
    for (let o = C.order; o >= 1; o--) {
      const ctxS = hist.slice(-o).join('');
      const m = C.tbl[o][ctxS];
      if (m) {
        let tot = 0; for (const k in m) tot += m[k];
        let x = rnd() * tot;
        for (const k in m) { x -= m[k]; if (x < 0) return [k, o]; }
      }
    }
    return ['\u0003', 0];
  }
  function genRemix(n) {
    const lang = S.lang, L = M.lang(lang), C = chain(lang, S.opt.order, S.opt.singleWords);
    const real = realSet(lang), used = {};
    const w = siteW(), x = M.expandSite(w);
    const t = { id: 1, character: S.character, dialect: dialectObj(L) };
    const ctx = M.newCtx(lang, S.seed, real);
    const stems = M.rankParts(ctx, L.specs.filter(e => e.kind === 'stem' && !e.flags.c), x, t, 's', {}, 0).slice(0, 12);
    const gens = M.rankParts(ctx, L.gens.filter(e => e.form === 'suf' || e.form === 'ja'), x, t, 'g', {}, 0).slice(0, 12);
    const out = [];
    if (C.n === 0) return out;
    for (let i = 1; i <= n; i++) {
      const rnd = mulberry(rng.hash(S.seed, 'remix', i));
      let got = null;
      for (let tries = 0; tries < 300 && !got; tries++) {
        const roll = rnd();
        let hist = Array.from('\u0002'.repeat(C.order)), pre = '', suf = null, how = 'chain', stem = null, gen = null;
        if (roll < S.opt.bias / 2 && stems.length) {
          stem = stems[Math.floor(rnd() * Math.min(6, stems.length))];
          pre = L.script === 'romaji' ? M.capFirst(stem.e.r) : (L.script ? stem.e.k : stem.e.text);
          pre = u(pre); hist = hist.concat(Array.from(pre)); how = 'stem + chain';
        } else if (roll < S.opt.bias && gens.length) {
          gen = gens[Math.floor(rnd() * Math.min(6, gens.length))];
          suf = u(L.script === 'romaji' ? gen.e.r : (L.script ? gen.e.k : gen.e.text)); how = 'chain + generic';
        }
        let s = pre, minO = 9;
        const maxLen = suf ? 7 : 14;
        while (Array.from(s).length < maxLen + pre.length) {
          const [c, o] = nextChar(C, hist, rnd);
          if (c === '\u0003') break;
          minO = Math.min(minO, o); s += c; hist.push(c);
        }
        if (suf) {
          if (Array.from(s).length < 2) continue;
          const j = L.script ? b(s + suf) : M.sufJoin(L, b(s), b(suf));
          if (!j) continue;
          s = u(j);
        }
        if (Array.from(s).length < 3 || s === pre) continue;
        const bs = b(s), low = M.lowerAll(bs);
        if (real[low] || used[low] || M.blocked(bs) || !M.wellFormed(L, bs)) continue;
        used[low] = true;
        if (L.script === 'kanji' && !s.endsWith('市')) s += '市';
        got = { mode: 'remix', name: s, parts: [pre || null, suf || null].filter(Boolean), how, stem: stem ? { text: u(stem.e.k || stem.e.text), f: stem.f, bt: stem.bt } : null,
          gen: gen ? { text: u(gen.e.k || gen.e.text), f: gen.f, bt: gen.bt } : null, order: C.order, minO, trainN: C.n, tries };
      }
      if (got) out.push(got);
    }
    return out;
  }
  const GEN = { morph: genMorph, remix: genRemix, desc: genDesc, feat: genFeat, old: genOld, map: n => genMap(n) };
  function generate(mode, n) {
    try { return GEN[mode](n); } catch (e) { console.error(e); return [{ mode, name: null, fail: String(e && e.message || e) }]; }
  }

  // ------------------------------------------------------------------ map mode (NEXT_PHASE_BRIEF 53 Part B, review Q8)
  // A whole map named at once with the per-map plan (ot_placename.assign: shapes, layers, twins, the feature budget):
  // a synthetic map (the site kinds of tests/square_organic_towns/test_shapegates.lua, same seeds) or the towns of an
  // imported game log (NAME lines). The set gets a region rating (1-5), the shape mix (target vs plan vs generated), the
  // names on a map, the review's Q7 numbers and a shape A/B test.
  const MAP_SITES = {
    river: 'river:1,bridge:.6,ford:.6,meadow:.6,plain:.5', confluence: 'river:1,confluence:1,ford:.6,bridge:.6,plain:.5',
    mouth: 'river:1,mouth:1,coast:.8,bay:.6,bridge:.7,market:.6', bend: 'river:1,bend:.9,meadow:.6,forest:.4',
    falls: 'river:1,falls:1,gorge:.5,rock:.4,forest:.4', lake: 'lake:1,mere:.8,edge:.7,forest:.5,meadow:.5',
    tarn: 'lake:1,tarn:1,mountain:.7,hill:.6,small:.6', coast: 'coast:1,sandy:.8,bay:.6,plain:.6',
    cliff: 'coast:1,cliff:1,rocky:.8,headland:.9,hilltop:.6', spit: 'coast:1,spit:1,headland:.8,sandy:.5',
    island: 'island:1,coast:1,sandy:.7,bay:.6', hill: 'hill:.8,hilltop:.7,slope:.6,heath:.4',
    pass: 'pass:1,mountain:.8,hill:.7,rock:.6,pine:.5', moor: 'moor:.8,heath:.6,hill:.6,spring:.6',
    vale: 'valley:1,vale:.8,forest:.6,meadow:.5', gorge: 'valley:1,gorge:1,river:1,rock:.7,slope:.7',
    forest: 'forest:.9,clearing:.8,oak:.7,edge:.6', edge: 'forest:.6,edge:.7,ash:.7,field:.4', plain: 'plain:.9,field:.8',
    marsh: 'marsh:.8,fen:.8,plain:.7,willow:.6',
  };
  const MAP_PRESETS = {
    valley: ['river', 'confluence', 'mouth', 'bend', 'falls', 'vale', 'plain', 'edge', 'forest', 'hill', 'marsh', 'river'],
    coast: ['coast', 'cliff', 'spit', 'island', 'mouth', 'plain', 'edge', 'hill', 'marsh', 'forest', 'coast'],
    lakes: ['lake', 'tarn', 'forest', 'edge', 'vale', 'hill', 'plain', 'river', 'moor', 'lake'],
    upland: ['hill', 'pass', 'moor', 'gorge', 'tarn', 'vale', 'forest', 'river', 'falls', 'plain'],
  };
  const SHAPE_COLORS = { plain: '#7a8691', single: '#8a6bbd', separate: '#2f7fb5', personal: '#3a9e8f', article: '#b5832f',
    qualifier: '#c0563f', frame: '#d1407a', saint: '#a8892a', whole: '#2e9e4b', civic: '#6b6bd1', character: '#e07b1a' };
  function tagsOf(str) { const w = {}; String(str).replace(/([A-Za-z_]+):([0-9.]+)/g, (m0, k, v) => { w[k] = Number(v); return m0; }); return w; }
  // the synthetic map of test_shapegates.makeMap (the same seeds give the same map)
  function synthMap(n, preset, seed, climate) {
    const kinds = MAP_PRESETS[preset] || MAP_PRESETS.valley;
    const U = rng.unit;
    const towns = [];
    const side = Math.max(16000, Math.sqrt(n / 16) * 16000);
    let tries = 0;
    while (towns.length < n && tries < n * 60) {
      tries++;
      const x = (U(seed * 3 + 1, tries, 'px') - 0.5) * side, y = (U(seed * 7 + 5, 'py', tries * 13 + 3) - 0.5) * side;
      if (towns.some(t => (t.x - x) ** 2 + (t.y - y) ** 2 < 1400 * 1400)) continue;
      const i = towns.length + 1;
      const kind = kinds[rng.hash(seed, 'kind', i) % kinds.length];
      const w = tagsOf(MAP_SITES[kind]);
      const cw = {}, nx = x / (side / 2), ny = y / (side / 2);
      const sideV = v => v > 0.3 ? Math.min(1, 0.4 + 0.6 * (v - 0.3) / 0.7) : null;
      const sv = { north: sideV(ny), south: sideV(-ny), east: sideV(nx), west: sideV(-nx) };
      for (const d in sv) if (sv[d] != null) cw[d] = sv[d];
      if (Math.max(Math.abs(nx), Math.abs(ny)) <= 0.25) cw.central = 0.8;
      let dir = null, dv = 0;
      for (const d of ['north', 'south', 'east', 'west']) if ((cw[d] || 0) > dv) { dir = d; dv = cw[d]; }
      const cue = { w: cw, dir };
      let alt = preset === 'upland' ? 150 + U(seed, 'alt', i) * 450 : 5 + U(seed, 'alt', i) * 110;
      if (w.river) {
        cue.river = x < 0 ? 1 : 2;
        cue.flow = Math.max(0, Math.min(1, (y + side / 2) / side));
        if (cue.flow <= 0.33) cw.lower = 0.6 + 0.4 * (1 - cue.flow / 0.33); else if (cue.flow >= 0.67) cw.upper = 0.6 + 0.4 * (cue.flow - 0.67) / 0.33;
        if (w.confluence) cw.confluence = 1;
        if (w.mouth) cw.mouth = 1;
        if (w.falls) cw.falls = 1;
        if (w.bend) cw.bend = 0.9;
        if (cue.river === 1) cw.mainvalley = 0.9;
        alt = alt * (0.4 + cue.flow);
      }
      if (preset === 'upland' && (w.hill || w.pass || w.mountain)) {
        cw.range = 0.8;
        if (U(seed, 'peak', i) < 0.4) cw.peak = 1;
        if (w.pass) cw.summit = 0.7;
      }
      if ((w.bay || 0) > 0 && preset === 'coast' && U(seed, 'bay', i) < 0.5) { cw.bay = 1; cw.bigbay = 1; cue.bigbay = true; }
      if (w.lake && preset === 'lakes' && U(seed, 'big', i) < 0.5) { cw.biglake = 1; cue.lake = true; cue.ldir = M.dirFrom(x - 1000, y); }
      if (climate && climate !== 'temperate') {
        const site = (M.CL.SITE || {})[climate] || {};
        for (const k in site) w[k] = Math.max(w[k] || 0, site[k]);
        if (climate === 'tropical' && (w.coast || 0) > 0) w.reef = 0.5;
        if (climate === 'tropical' && (w.bay || w.island)) w.lagoon = 0.8;
        for (const k in w) if (M.vetoTag(climate, k)) delete w[k];
      }
      const cap = 150 + floor(U(seed, 'cap', i) * 2300);
      const ch = i === 3 || i === 9;
      if (ch) { w.character = 1; w.church = 0.4; }
      if (cap > 1800) { w.market = 0.8; w.big = 0.8; } else if (cap < 400) w.small = 0.6;
      towns.push({ id: 1000 + i * 7, name: 'T' + i, x, y, w, ranked: M.ranked(w), cap, character: ch, cue, river: w.river != null,
        lake: w.lake != null, alt, kind });
    }
    return towns;
  }
  const floor = Math.floor;
  // a game log's NAME lines (the last map load with NAME lines; "Map seed text:" splits the loads)
  function parseLog(text) {
    const lines = text.split('\n');
    const loads = [];
    lines.forEach((l, i) => { const m = /Map seed text: (.*)$/.exec(l); if (m) loads.push([i, m[1].trim()]); });
    if (!loads.length) loads.push([0, null]);
    let pick = null;
    loads.forEach(([s0, st], k) => {
      const e0 = k + 1 < loads.length ? loads[k + 1][0] : lines.length;
      for (let i = s0; i < e0; i++) if (lines[i].indexOf('NAME town=') >= 0) { pick = [s0, e0, st]; break; }
    });
    if (!pick) return null;
    const kv = s => { const o = {}; s.replace(/(\w+)=(\S*)/g, (m0, k, v) => { o[k] = v; return m0; }); return o; };
    const und = v => (v || '').replace(/_/g, ' ');
    const pairs = s => (s || '').split(',').map(p => { const i = p.lastIndexOf(':'); return i > 0 ? [p.slice(0, i), Number(p.slice(i + 1))] : null; }).filter(p => p && !isNaN(p[1]));
    const towns = []; let summary = null, words = null;
    for (let i = pick[0]; i < pick[1]; i++) {
      const l = lines[i];
      const j = l.indexOf('NAME town=');
      if (j >= 0) {
        const f = kv(l.slice(j + 5));
        const parts = (f.parts || '-+-+-').split('+');
        towns.push({ id: f.town, old: und(f.old), new: und(f.new), src: f.src, parts: [0, 1, 2].map(k => parts[k] && parts[k] !== '-' ? und(parts[k]) : null),
          feature: f.feature, tags: pairs(f.tags), cue: pairs(f.cue), river: f.river && f.river !== '-' ? und(f.river) : null,
          lake: f.lake && f.lake !== '-' ? und(f.lake) : null, dialect: f.dialect, read: f.read, score: Number(f.score || 0),
          character: f.character === 'true', char: f.char && f.char !== '-' ? f.char : null, cap: Math.floor(Number(f.cap || 0)),
          x: f.x != null && f.x !== '-' ? Number(f.x) : null, y: f.y != null && f.y !== '-' ? Number(f.y) : null,
          alt: f.alt != null && f.alt !== '-' ? Number(f.alt) : null, shape: f.shape, layer: f.layer });
      }
      const k2 = l.indexOf('NAMES words');
      if (k2 >= 0) words = kv(l.slice(k2 + 11));
      const k3 = l.search(/NAMES (?!words|shapes|survey|offshoot)/);
      if (k3 >= 0 && /\bgen=|\blang=|\bmode=/.test(l)) summary = kv(l.slice(k3 + 6));
    }
    if (!towns.length) return null;
    return { seedText: pick[2], towns, summary: summary || {}, climate: words && words.climate && words.climate !== '-' ? words.climate : null,
      imported: new Date().toISOString() };
  }
  // the log's towns as assign inputs: weights from the tags (score / specificity) and the cues, the river / lake by name
  function townsFromLog(mp) {
    const comp = {}; let nComp = 0;
    return mp.towns.map((t, i) => {
      const w = {};
      for (const [k, v] of t.tags) if (M.TAG_INDEX[k]) w[k] = Math.min(1, v / (M.SPEC[k] || 1));
      const cue = { w: {} };
      for (const [k, v] of (t.cue || [])) if (M.TAG_INDEX[k]) cue.w[k] = Math.min(1, v);
      let dir = null, dv = 0;
      for (const d of ['north', 'south', 'east', 'west']) if ((cue.w[d] || 0) > dv) { dir = d; dv = cue.w[d]; }
      cue.dir = dir;
      if (t.river) { if (comp[t.river] == null) comp[t.river] = ++nComp; cue.river = comp[t.river]; }
      const hasXY = typeof t.x === 'number' && !isNaN(t.x) && typeof t.y === 'number' && !isNaN(t.y);
      return { id: Number(t.id) || 1000 + i, name: t.old, x: hasXY ? t.x : (i % 7) * 6000, y: hasXY ? t.y : floor(i / 7) * 6000, w,
        ranked: M.ranked(w), cap: t.cap || 0, character: t.character ? (t.char || true) : false, river: !!t.river, lake: !!t.lake,
        cue, alt: t.alt == null ? undefined : t.alt, game: t.new, gameShape: t.shape, hasXY };
    });
  }
  function mapSource() { return S.mapSrc === 'log' && (S.imported || D.map) ? (S.imported || D.map) : null; }
  // the target shape shares (the review's Q1 table, the climate's table; the page's sliders on top)
  function quotaKey(lang, clim) { return baseLang(lang) + '|' + (clim || 'temperate'); }
  function applyQuota(lang, clim) {
    const L = M.lang(lang); const cl = M.climateOf(L, clim);
    cl._q0 = cl._q0 || cl.quota;
    const ed = (S.quotaEdit || {})[quotaKey(lang, clim)];
    cl.quota = ed ? Object.assign({}, cl._q0, ed) : cl._q0;
    return cl;
  }
  let MAPRUN = null;
  function runMap(n) {
    const src = mapSource();
    const lang = src && src.summary && src.summary.gen && D.lang[baseLang(src.summary.gen)] ? src.summary.gen : S.lang;
    const clim = src && src.climate ? src.climate : (S.climate || 'temperate');
    const towns = src ? townsFromLog(src) : synthMap(n, S.mapPreset || 'valley', S.seed, clim);
    applyQuota(lang, clim);
    // (NEXT_PHASE_BRIEF 60: the naming rules, "descriptive (§60)" or the review's "§53", to compare)
    const [res, st] = M.assign(towns, { lang, seed: S.seed, real: realSet(lang), climate: clim, year: S.mapYear || 1850, rules: S.mapRules || 's61' });
    MAPRUN = { lang, clim, towns, res, st, src: src ? 'log' : 'synthetic', key: [lang, clim, src ? 'log:' + (src.seedText || '-') : (S.mapPreset || 'valley'), S.seed, towns.length, S.mapYear || 1850, S.mapRules || 's60'].join('|') };
    return MAPRUN;
  }
  function genMap(n) {
    const R = runMap(n);
    return R.res.map((r, i) => {
      const inf = r.info && typeof r.info === 'object' ? r.info : null;
      return { mode: 'map', name: r.new ? u(r.new) : null, fail: r.why, parts: partsOf(inf), info: inf, river: r.river ? u(r.river) : null,
        lake: r.lake ? u(r.lake) : null, ti: i, shape: inf ? inf.shape : null, layer: inf ? inf.layer : null, game: R.towns[i].game };
    });
  }
  // the review's Q7 numbers over the map (as tests/square_organic_towns/test_shapegates.lua gates them)
  function q7(R) {
    const { res, st, towns, lang, clim } = R;
    const L = M.lang(lang), Q = M.climateOf(L, clim).quota, N = res.length || 1;
    const shapes = {}; let tok = 0, maxTok = 0, quiet = 0, ideas3 = 0, mix = 0, compassBad = 0;
    for (const r of res) {
      const inf = r.info || {};
      const sh = inf.shape || 'plain'; shapes[sh] = (shapes[sh] || 0) + 1;
      const k = M.tokens(r.new); tok += k; if (k > maxTok) maxTok = k;
      if (inf.quiet) quiet++;
      if (M.ideas(inf.sE, inf.gE, inf.aE, inf.twin != null) > 2) ideas3++;
      if (inf.sE && inf.gE && !M.compatible(L, inf.sE.grp, inf.gE.grp)) mix++;
      const a = inf.aE;
      if (a && (a.mapDir || (a.qkind === 'compass' && inf.twin == null))) compassBad++;
    }
    const featN = {};
    for (const stem in (st.ctx.featWords || {})) {
      let n = 0;
      for (const r of res) if (u(M.lowerAll(r.new)).indexOf(u(stem)) >= 0) n++;
      featN[u(stem)] = n;
    }
    const roots = {};
    if (!L.script) for (const r of res) if (r.info && r.info.twin == null && r.info.reuse == null) for (const k of M.extraKeys(L, r.new, st.ctx.featWords)) if (k[0] === '^') roots[k] = (roots[k] || 0) + 1;
    const cap = Math.max(1, Math.ceil(N / 12));
    const rootOver = Object.keys(roots).filter(k => roots[k] > cap).map(k => u(k.slice(1)) + ' ×' + roots[k]);
    const featOver = Object.keys(featN).filter(k => featN[k] > 2).map(k => k + ' ×' + featN[k]);
    const words = M.climateOf(L, clim).words || 1;
    const wLim = lang === 'usa' ? Math.max(1.8, words + 0.15) : (lang === 'en' ? Math.max(1.4, words + 0.05) : null);
    const pct = v => Math.round(v * 100) + ' %';
    return [
      { k: 'Frame share', v: pct((shapes.frame || 0) / N), lim: '≤ ' + pct((Q.frame || 0) + 0.05), ok: (shapes.frame || 0) / N <= (Q.frame || 0) + 0.05 + 1e-9 },
      { k: 'Whole-name share', v: pct((shapes.whole || 0) / N), lim: '≤ ' + pct((Q.whole || 0) + 0.05), ok: (shapes.whole || 0) / N <= (Q.whole || 0) + 0.05 + 1e-9 },
      { k: 'Words per name', v: (tok / N).toFixed(2), lim: wLim ? '≤ ' + wLim.toFixed(2) : '-', ok: wLim == null || tok / N <= wLim + 1e-9 },
      { k: 'Most words in a name', v: maxTok, lim: '≤ 3', ok: maxTok <= 3 },
      { k: 'Named features in 3+ names', v: featOver.join(', ') || 'none', lim: 'none', ok: featOver.length === 0 },
      { k: 'Roots over 1 per 12 towns', v: rootOver.join(', ') || 'none', lim: 'none (twins excepted)', ok: rootOver.length === 0 || (st.budget && st.budget.over > 0) },
      { k: 'Names mixing two dialects', v: mix, lim: '0', ok: mix === 0 },
      { k: 'Names with 3+ feature ideas', v: ideas3, lim: '0', ok: ideas3 === 0 },
      { k: 'Compass words off their twin', v: compassBad, lim: '0', ok: compassBad === 0 },
      { k: 'Quiet names (no terrain word)', v: pct(quiet / N), lim: '≥ 35 % (soft)', ok: quiet / N >= 0.35 },
    ];
  }
  function lowerAllU(s) { return u(M.lowerAll(b(String(s || '')))); }
  // the names on a simple map: dots by shape, labels, the dialect border, names that spend a named feature in colour
  function mapSvg(R) {
    const { towns, res, st } = R;
    if (!towns.length) return '';
    const xs = towns.map(t => t.x), ys = towns.map(t => t.y);
    const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
    const W = 900, H = Math.max(360, Math.round(W * (y1 - y0 + 1) / (x1 - x0 + 1)) || 360), pad = 70;
    const sx = x => pad + (x - x0) / Math.max(1, x1 - x0) * (W - 2 * pad), sy = y => H - pad - (y - y0) / Math.max(1, y1 - y0) * (H - 2 * pad);
    const stems = Object.keys(st.ctx.featWords || {}).map(s => u(s));
    let border = '';
    const A = st.ctx.areas;
    if (A && A.c && A.n) {
      const d = { x: A.n.y, y: -A.n.x }, big = 1e6;
      const line = (cx, cy, dash) => `<line x1="${sx(cx - d.x * big)}" y1="${sy(cy - d.y * big)}" x2="${sx(cx + d.x * big)}" y2="${sy(cy + d.y * big)}" stroke="var(--muted)" stroke-dasharray="${dash}" stroke-width="1.2"/>`;
      border = line(A.c.x, A.c.y, '6 5');
      if (A.three && A.fringe != null) border += line(A.c.x + A.n.x * A.coreK * A.fringe, A.c.y + A.n.y * A.coreK * A.fringe, '2 4');
    }
    const roleOf = t => { const dd = M.dialectAt(st.ctx, t.x, t.y); return dd ? u(dd.name) : ''; };
    const pts = towns.map((t, i) => {
      const r = res[i], inf = r && r.info || {};
      const nm = u(r ? r.new : t.name);
      const feat = stems.find(s => lowerAllU(nm).indexOf(s) >= 0);
      const col = SHAPE_COLORS[inf.shape] || SHAPE_COLORS.plain;
      return `<g><title>${esc(nm)} · ${esc(inf.shape || '-')} · ${esc(inf.layer || '-')} · ${esc(roleOf(t))}${feat ? ' · names ' + esc(feat) : ''}</title>` +
        `<circle cx="${sx(t.x).toFixed(1)}" cy="${sy(t.y).toFixed(1)}" r="${4 + Math.min(5, (t.cap || 0) / 500)}" fill="${col}"/>` +
        `<text x="${(sx(t.x) + 8).toFixed(1)}" y="${(sy(t.y) + 4).toFixed(1)}" font-size="12.5" fill="${feat ? 'var(--accent)' : 'var(--ink)'}"${feat ? ' font-weight="700"' : ''}>${esc(nm)}</text></g>`;
    }).join('');
    return `<svg viewBox="0 0 ${W} ${H}" class="mapsvg" role="img" aria-label="The map's names at their positions">` +
      `<rect x="0" y="0" width="${W}" height="${H}" fill="var(--bg)" rx="8"/>${border}${pts}` +
      `<text x="${W - 12}" y="18" text-anchor="end" font-size="11" fill="var(--muted)">N ↑ · dashed: dialect border${A && A.three ? ' (and the edge area)' : ''}</text></svg>`;
  }
  // the shape mix: the review's table (the climate's), the target (editable), the plan's counts, what the names got
  function shapeMix(R) {
    const L = M.lang(R.lang), cl = M.climateOf(L, R.clim), N = R.res.length;
    const base = cl._q0 || cl.quota, cur = cl.quota, used = R.st.shapes.used || {}, plan = R.st.shapes.quota || {};
    const rows = M.SHAPES.map(sh => {
      const t = sh === 'plain' ? Math.max(0, 1 - Object.keys(cur).reduce((a, k) => a + (k !== 'plain' ? cur[k] : 0), 0)) : (cur[sh] || 0);
      const r0 = sh === 'plain' ? Math.max(0, 1 - Object.keys(base).reduce((a, k) => a + base[k], 0)) : (base[sh] || 0);
      const g = (used[sh] || 0) / Math.max(1, N);
      return { sh, t, r0, g, plan: plan[sh] || 0, n: used[sh] || 0 };
    }).filter(x => x.t > 0 || x.n > 0 || x.r0 > 0);
    const bar = (v, col) => `<span class="bar" style="width:${Math.round(Math.min(1, v) * 160)}px;background:${col}"></span>`;
    return `<table class="ctable mixtable"><tr><th>Shape</th><th>Review Q1</th><th>Target</th><th>Plan</th><th>Got</th><th>Target / got</th></tr>` +
      rows.map(x => `<tr><th><span class="dot" style="background:${SHAPE_COLORS[x.sh] || '#888'}"></span>${esc(x.sh)}</th><td class="muted">${Math.round(x.r0 * 100)} %</td>` +
        `<td>${x.sh === 'plain' ? Math.round(x.t * 100) + ' %' : `<input type="number" min="0" max="1" step="0.01" data-quota="${esc(x.sh)}" value="${(+x.t).toFixed(2)}" aria-label="${esc(x.sh)} target share">`}</td>` +
        `<td>${x.plan || '-'}</td><td>${x.n} (${Math.round(x.g * 100)} %)</td><td>${bar(x.t, 'var(--line)')}<br>${bar(x.g, SHAPE_COLORS[x.sh] || '#888')}</td></tr>`).join('') +
      `</table><p class="muted small">Review Q1: the share from real gazetteers (the review's table; the climate's own on another climate). Target: the share the plan hands out (edit it: the map re-runs, the export carries it). Plan: the counts planShapes gave; Got: the shapes of the names (a shape whose names didn't fit goes plain).</p>`;
  }
  // the shape A/B test: the same town named in two shapes, from the map's context
  const AB_SHAPES = ['plain', 'single', 'separate', 'personal', 'article', 'qualifier', 'frame', 'saint', 'whole', 'civic'];
  let AB = null;
  function abFor(R, i) {
    const st = R.st, q0 = st.qs && st.qs[i], inf = R.res[i] && R.res[i].info;
    if (!q0 || !inf) return null;
    const mine = inf.shape || 'plain';
    const clone = () => {
      const c = Object.assign({}, st.ctx);
      for (const k of ['used', 'usedLower', 'specUse', 'genUse', 'affUse', 'featUse', 'shapeUse', 'riverFrame']) c[k] = Object.assign({}, st.ctx[k] || {});
      c.plainBases = (st.ctx.plainBases || []).slice(); c.budget = null; c.wordAllow = null;
      delete c.used[R.res[i].new]; delete c.usedLower[M.lowerAll(R.res[i].new)];
      return c;
    };
    const pack = (bName, bShape) => {
      const a = { name: u(R.res[i].new), shape: mine }, bb = { name: u(bName), shape: bShape };
      const swap = rng.unit(S.seed, 'abside', i) < 0.5;
      return { i, site: M.ranked(R.towns[i].w).slice(0, 5).map(x => x[0]), A: swap ? bb : a, B: swap ? a : bb };
    };
    const order = AB_SHAPES.filter(s => s !== mine).sort((a, c) => rng.hash(S.seed, 'ab', i, a) - rng.hash(S.seed, 'ab', i, c));
    // (the same base in two shapes first: "Mytmere" and "Mytmere-in-the-Vale", "Arunmouth" and "Lower Arunmouth")
    const L = M.lang(R.lang), base = inf.base;
    if (base && inf.aE && inf.aE.hasS && mine !== 'character') return pack(base, M.baseShape(L, { s: { e: inf.sE }, g: { e: inf.gE } }, st.ctx.quota));
    if (base && !inf.aE && !L.script) {
      const x = M.expandSite(q0.w || {});
      for (const sh of order.filter(o => o === 'qualifier' || o === 'frame' || o === 'saint')) {
        let best = null, bf = -Infinity;
        for (const a of L.affixes) {
          if (a.shape !== sh || a.flags.k || a.flags.v || a.mapDir || !a.hasS || !M.fillable(L, a, q0)) continue;
          if (sh === 'qualifier' && (a.qkind === 'compass' || a.qkind === 'small' || a.qkind === 'big')) continue;
          if (sh === 'frame' && M.tokens(base) > 1) continue;
          if (M.repeats(a, base)) continue;
          const f = M.fit(a, x)[0];
          if (f > bf) { bf = f; best = a; }
        }
        if (best && bf > 0) {
          const nm = M.fillAffix(L, best, base, Object.assign({ seed: S.seed }, q0));
          if (nm && nm !== R.res[i].new) return pack(nm, sh);
        }
      }
    }
    for (const sh of order) {
      const q = Object.assign({}, q0, { shape: sh, quiet: false, qualMode: sh === 'qualifier' ? 'site' : null, qualKind: null, blocked: null });
      const [nm, info] = M.nameTown(clone(), q);
      if (nm && info && info.shape === sh && nm !== R.res[i].new) return pack(nm, sh);
    }
    return null;
  }
  function renderMapPanel(R) {
    const rt = (S.mapRatings || {})[R.key];
    const qs = q7(R);
    const src = mapSource();
    const ab = AB && AB.key === R.key ? AB : null;
    const sf = M.shapeFields(R.st).map(e => e[0] + '=' + u(String(e[1]))).join(' ');
    return `<div class="mappanel">` +
      `<div class="card"><div class="reshead"><h3>The whole map</h3><span class="muted small">${esc(R.src === 'log' ? 'the imported log\'s sites' : 'a synthetic ' + (S.mapPreset || 'valley') + ' map')} · ${R.res.length} towns · ${esc(LANG_NAMES[R.lang] || R.lang)} · ${esc(R.clim)} · from ${S.mapYear || 1850}</span></div>` +
      `<div class="listbar"><label class="pick">Map <select id="mapPreset">${Object.keys(MAP_PRESETS).map(p => opt(p, p, (S.mapPreset || 'valley') === p && S.mapSrc !== 'log')).join('')}${(S.imported || D.map) ? opt('log', 'imported log', S.mapSrc === 'log') : ''}</select></label>` +
      `<label class="pick">Rules <select id="mapRules">${opt('s61', 'evocative (§61)', (S.mapRules || 's61') === 's61')}${opt('s60', 'descriptive (§60)', S.mapRules === 's60')}${opt('s53', 'review (§53)', S.mapRules === 's53')}</select></label>` +
      `<label class="pick">Start year <input type="number" id="mapYear" min="1800" max="2050" value="${S.mapYear || 1850}"></label>` +
      `<label class="pick">Game log <input type="file" id="logFile" accept=".txt,.log,.gz"></label>` +
      `${src && src.towns ? `<span class="muted small">${src.towns.length} towns from ${esc(src.seedText || '-')}${src.climate ? ' · ' + esc(src.climate) : ''}</span>` : ''}</div>` +
      `<p class="small" style="margin:6px 0">Sounds like one region? ${[1, 2, 3, 4, 5].map(v => `<button class="btn small${rt && rt.rating === v ? ' primary' : ''}" data-maprate="${v}">${v}</button>`).join(' ')} <span class="muted">${rt ? 'rated ' + rt.rating : '1 = a jumble, 5 = one region'}</span></p>` +
      `<p class="muted small"><code>NAMES shapes ${esc(sf)}</code></p>${mapSvg(R)}</div>` +
      `<div class="cgrid"><section class="card"><h3>Shape mix</h3>${shapeMix(R)}</section>` +
      `<section class="card"><h3>Q7 numbers</h3><table class="ctable">${qs.map(x => `<tr><th>${esc(x.k)}</th><td>${esc(String(x.v))}</td><td class="muted">${esc(x.lim)}</td><td>${x.ok ? '<span class="pill ok">ok</span>' : '<span class="pill warn">over</span>'}</td></tr>`).join('')}</table></section>` +
      `<section class="card"><h3>Shape A/B</h3><p class="muted small">The same town in two shapes (its own and another one that fits); pick the better. The votes go into the export, summed per shape.</p>` +
      (ab && ab.t ? `<p class="small">Site: ${ab.t.site.map(s => `<span class="pill">${esc(s)}</span>`).join(' ')}</p><div class="abrow">` +
        ['A', 'B'].map(k => `<button class="btn abpick" data-abpick="${k}"><b>${esc(ab.t[k].name)}</b><br><span class="muted small">${esc(ab.t[k].shape)}</span></button>`).join('') +
        `</div><p><button class="btn small" data-abpick="skip">Skip</button> <button class="btn small" id="abNext">Another town</button></p>`
        : `<p><button class="btn small" id="abNext">Start</button> <span class="muted small">${ab ? 'no second shape fits that town' : ''}</span></p>`) +
      `<p class="muted small">${(S.ab || []).length} votes so far.</p></section></div></div>`;
  }
  function abNext(R) {
    const n = R.res.length;
    for (let k = 0; k < n; k++) {
      const i = (((S.abI || 0) + k) % n);
      const t = abFor(R, i);
      if (t) { S.abI = i + 1; AB = { key: R.key, t }; return; }
    }
    AB = { key: R.key, t: null };
  }
  function shapeSummary() {
    // ratings, A/B votes and region ratings added up per shape (the export's byShape)
    const out = {};
    const get = sh => (out[sh] = out[sh] || { up: 0, down: 0, abShown: 0, abPicked: 0, mapRated: 0, mapScore: 0 });
    for (const r of Object.values(S.ratings)) if (r.shape) { const o = get(r.shape); if (r.r > 0) o.up++; else o.down++; }
    for (const v of (S.ab || [])) {
      if (v.pick === 'skip') continue;
      get(v.A.shape).abShown++; get(v.B.shape).abShown++;
      get(v[v.pick].shape).abPicked++;
    }
    for (const m of Object.values(S.mapRatings || {})) for (const sh in (m.shapes || {})) { const o = get(sh); o.mapRated += m.shapes[sh]; o.mapScore += m.shapes[sh] * m.rating; }
    for (const sh in out) if (out[sh].mapRated) out[sh].mapAvg = Math.round(out[sh].mapScore / out[sh].mapRated * 100) / 100;
    return out;
  }

  // ------------------------------------------------------------------ rendering: controls
  function opt(v, label, sel) { return `<option value="${esc(v)}"${sel ? ' selected' : ''}>${esc(label)}</option>`; }
  function renderControls() {
    $('#lang').innerHTML = D.pn.LANGS.filter(l => D.lang[baseLang(l)]).map(l => opt(l, LANG_NAMES[l] || l, l === S.lang)).join('');
    const L = M.lang(S.lang);
    const ds = (L.groups || []).map(d => u(d));
    if (S.dialect !== 'auto' && S.dialect !== 'none' && ds.indexOf(S.dialect) < 0) S.dialect = 'auto';
    $('#dialect').innerHTML = opt('auto', 'Dialect areas (as in game)', S.dialect === 'auto') + opt('none', 'None', S.dialect === 'none') +
      ds.map(d => opt(d, d, S.dialect === d)).join('');
    $('#dialect').disabled = ds.length === 0;
    $('#seed').value = S.seed;
    $('#affixP').value = S.affixP; $('#affixPv').textContent = Math.round(S.affixP * 100) + '%';
    $('#character').checked = !!S.character;
    if ($('#budget')) $('#budget').checked = S.budget !== false;
    if ($('#climate')) $('#climate').value = S.climate || 'temperate';
    $('#shared').value = S.shared ? '1' : '0';
    $('#count').value = S.opt.count;
    $$('#modes button').forEach(bt => bt.setAttribute('aria-pressed', String((S.view === 'all' && bt.dataset.mode === 'all') || (S.view !== 'all' && bt.dataset.mode === S.mode))));
  }
  function renderSite() {
    const w = siteW();
    $('#presets').innerHTML = Object.keys(D.presets).map(p => `<button class="chip" data-preset="${esc(p)}" aria-current="${S.preset === p}">${esc(p)}</button>`).join('');
    $('#tags').innerHTML = GROUPS.map(([g, tags]) => {
      const on = tags.filter(t => S.site[t] >= 0.2).length;
      return `<details${on || g === 'Rivers' || g === 'Lakes' ? ' open' : ''}><summary>${esc(g)}${on ? ` <span class="cnt">${on}</span>` : ''}</summary>` +
        tags.map(t => {
          const v = S.site[t];
          const act = v >= 0.2;
          return `<div class="tagrow${act ? ' on' : ''}"><label><input type="checkbox" data-tag="${t}"${act ? ' checked' : ''}> ${t}</label>` +
            `<input type="range" min="0.2" max="1" step="0.05" value="${act ? v : 0.8}" data-tagw="${t}"${act ? '' : ' disabled'} aria-label="${t} strength">` +
            `<span class="tv">${act ? (+v).toFixed(2) : ''}</span></div>`;
        }).join('') + '</details>';
    }).join('');
    const ranked = M.ranked(w);
    $('#ranked').innerHTML = ranked.length ? ranked.slice(0, 8).map(r => `<span class="pill">${esc(r[0])} ${f2(r[1])}</span>`).join(' ') : '<span class="muted">No tags: only the "any" parts fit.</span>';
  }

  // ------------------------------------------------------------------ rendering: results
  let LAST = { grid: [], all: {} }, LOCK = null;
  const rkey = r => S.lang + '|' + r.mode + '|' + r.name;
  function card(r, idx, compact) {
    if (!r.name) return `<div class="ncard fail">no name (${esc(r.fail || '-')})</div>`;
    const k = rkey(r), rt = S.ratings[k] ? S.ratings[k].r : 0, pin = !!S.pinned[k];
    let sub = '';
    if (r.mode === 'remix') sub = r.how;
    else if (r.mode === 'old') sub = (r.applied && r.applied.length ? 'from ' + r.modern : 'no spelling rule matched') + (r.how !== 'spelling' ? ' · ' + r.how : '');
    else if (r.mode === 'map') sub = [r.parts.join(' + '), r.shape, r.layer, r.game ? 'game: ' + r.game : null].filter(Boolean).join(' · ');
    else sub = r.parts.join(' + ');
    return `<div class="ncard${rt > 0 ? ' up' : ''}${rt < 0 ? ' down' : ''}${pin ? ' pinned' : ''}" data-idx="${idx}" tabindex="0">` +
      `<div class="nm">${esc(r.name)}</div>${compact ? '' : `<div class="pt">${esc(sub)}</div>`}` +
      `<div class="acts"><button class="ic" data-act="up" title="Good" aria-pressed="${rt > 0}">👍</button><button class="ic" data-act="down" title="Bad" aria-pressed="${rt < 0}">👎</button>` +
      `<button class="ic" data-act="pin" title="Pin" aria-pressed="${pin}">📌</button></div></div>`;
  }
  let IDX = [];
  function renderResults() {
    IDX = [];
    const reg = r => { IDX.push(r); return IDX.length - 1; };
    const w = siteW();
    const siteTxt = M.ranked(w).slice(0, 5).map(r => r[0]).join(', ') || 'no tags';
    if (S.view === 'all') {
      const n = Math.max(6, Math.min(20, Math.round(S.opt.count / 4)));
      $('#resTitle').textContent = `All modes · ${n} names each · ${LANG_NAMES[S.lang]} · ${siteTxt}${S.character ? ' · character town' : ''}`;
      $('#results').className = 'allmodes';
      $('#results').innerHTML = MODES.filter(m => m.id !== 'map').map(m => {
        const rs = generate(m.id, n);
        return `<section class="col"><h3>${esc(m.name)}</h3><p class="muted small">${esc(m.desc)}</p><div class="stack">` +
          (rs.length ? rs.map(r => card(r, reg(r), false)).join('') : '<p class="muted small">No names for this site in this language.</p>') + '</div></section>';
      }).join('');
    } else {
      const rs = generate(S.mode, S.opt.count);
      $('#resTitle').textContent = `${MODE[S.mode].name} · ${rs.filter(r => r.name).length} names · ${LANG_NAMES[S.lang]} · ${siteTxt}${S.character ? ' · character town' : ''}`;
      $('#resDesc').textContent = MODE[S.mode].desc;
      if (S.mode === 'map' && MAPRUN) {
        $('#resTitle').textContent = `Whole map (plan) · ${rs.filter(r => r.name).length} towns · ${LANG_NAMES[MAPRUN.lang] || MAPRUN.lang} · ${MAPRUN.clim}`;
        $('#results').className = '';
        $('#results').innerHTML = renderMapPanel(MAPRUN) + '<div class="grid">' + rs.map(r => card(r, reg(r), false)).join('') + '</div>';
      } else {
        $('#results').className = 'grid';
        $('#results').innerHTML = rs.length ? rs.map(r => card(r, reg(r), false)).join('') : '<p class="muted">No names for this site in this language (try another mode or more tags).</p>';
      }
    }
    $('#resDesc').hidden = S.view === 'all';
    if (LOCK != null && IDX[LOCK]) showWhy(IDX[LOCK]); else { LOCK = null; showWhy(IDX.find(r => r.name) || null); }
  }
  function tagChips(tl) { return (tl || []).map(p => `<span class="pill">${esc(p[0])}${p[1] !== 1 ? ':' + (+p[1]).toFixed(2).replace(/0+$/, '').replace(/\.$/, '') : ''}</span>`).join(' '); }
  function entryLine(e) {
    if (!e) return '-';
    const bits = [];
    if (e.form) bits.push('form ' + e.form);
    if (e.kind) bits.push(e.kind);
    if (e.grp) bits.push('@' + u(e.grp));
    if (e.rare) bits.push('rare');
    if (e.cls) bits.push('=' + u(e.cls));
    const fl = Object.keys(e.flags || {}); if (fl.length) bits.push(fl.map(f => '+' + f).join(' '));
    if (e.river) bits.push('the river\'s name');
    return `${tagChips(e.tl)} <span class="muted">${esc(bits.join(' · '))}</span>`;
  }
  function showWhy(r) {
    const el = $('#why');
    if (!r) { el.innerHTML = '<p class="muted">Hover a name for what produced it; click to keep it here.</p>'; return; }
    let h = `<div class="whyhead"><b class="big">${esc(r.name || '-')}</b> <span class="muted">${esc(MODE[r.mode].name)} · ${LOCK != null ? 'kept (click the name again or <button class="btn small" id="unlock">release</button>)' : 'hover a name for its breakdown, click to keep it'}</span></div>`;
    if (r.mode === 'remix') {
      h += `<table class="kvt"><tr><th>How</th><td>${esc(r.how)}</td></tr>`;
      if (r.stem) h += `<tr><th>Stem</th><td>${esc(r.stem.text)} · fit ${f2(r.stem.f)} (${esc(r.stem.bt || '-')})</td></tr>`;
      if (r.gen) h += `<tr><th>Generic</th><td>-${esc(r.gen.text)} · fit ${f2(r.gen.f)} (${esc(r.gen.bt || '-')})</td></tr>`;
      h += `<tr><th>Chain</th><td>order ${r.order} (shortest context used: ${r.minO > 8 ? '-' : r.minO}), trained on ${r.trainN} game names, ${r.tries + 1} tries</td></tr></table>`;
    } else if (r.info) {
      const i = r.info, dbg = i.dbg || {};
      h += `<table class="kvt">`;
      if (r.mode === 'old') h += `<tr><th>Modern</th><td>${esc(r.modern)} · ${esc(r.how)}${r.applied && r.applied.length ? '<br>' + r.applied.map(esc).join('<br>') : ''}</td></tr>`;
      h += `<tr><th>Base</th><td>${esc(u(i.base))}</td></tr>`;
      h += `<tr><th>Stem</th><td><b>${esc(u(i.spec))}</b> · fit ${f2(dbg.sF)} via <b>${esc(i.specTag || '-')}</b> (× SPEC_K ${M.C.SPEC_K})<br>${entryLine(i.sE)}</td></tr>`;
      h += `<tr><th>Generic</th><td><b>${esc(u(i.gen))}</b> · fit ${f2(dbg.gF)} via <b>${esc(i.genTag || '-')}</b><br>${entryLine(i.gE)}</td></tr>`;
      if (dbg.pair) h += `<tr><th>Pair bonus</th><td>+${f2(dbg.pair)} (stem and generic name two features)</td></tr>`;
      h += `<tr><th>Affix</th><td>${i.affix ? `<b>${esc(u(i.affix))}</b> · ${f2(dbg.affixScore)} over the cost<br>${entryLine(i.aE)}` : '<span class="muted">none</span>'}</td></tr>`;
      if (r.river || r.lake) h += `<tr><th>Water</th><td>${r.river ? 'river ' + esc(r.river) : ''}${r.river && r.lake ? ' · ' : ''}${r.lake ? 'lake ' + esc(r.lake) : ''}</td></tr>`;
      h += `<tr><th>Dialect</th><td>${esc(i.dialect ? u(i.dialect) : '-')}</td></tr>`;
      h += `<tr><th>Score</th><td>${f2(i.score)}${dbg.wide ? ' · from the wide search (no unique name in the top ones)' : ''}</td></tr>`;
      const xs = Object.keys(dbg.x || {}).sort((a, c) => dbg.x[c] - dbg.x[a]).slice(0, 10);
      h += `<tr><th>Site</th><td>${xs.map(t => `<span class="pill">${esc(t)} ${f2(dbg.x[t])}</span>`).join(' ')}</td></tr></table>`;
      if (dbg.alts && dbg.alts.length) {
        h += `<p class="muted small">Top candidates before uniqueness and affixes:</p><ol class="alts">` +
          dbg.alts.map(a => `<li>${esc(u(a.base))} <span class="muted">${esc(u(a.s))}+${esc(u(a.g))} ${f2(a.sc)}</span></li>`).join('') + '</ol>';
      }
    } else h += `<p class="muted">${esc(r.fail || '')}</p>`;
    el.innerHTML = h;
  }

  // ------------------------------------------------------------------ tabs
  function renderTabs() {
    $$('#tabs button').forEach(bt => bt.setAttribute('aria-selected', String(bt.dataset.tab === S.tab)));
    const f = { map: renderMap, lists: renderLists, consts: renderConsts, opts: renderOpts, rated: renderRated, stop: renderStop, port: renderPort, export: renderExport }[S.tab];
    $('#tabbody').innerHTML = '';
    if (f) f($('#tabbody'));
  }
  function mapLabNames(mp) {
    // this map's towns through the lab's engine (current edits) with the whole-map plan (assign): the log's sites,
    // positions (x / y on NAME lines from 2026-10-14 Part B; a grid before), rivers and lakes by name, the log's climate
    const lang = (mp.summary && mp.summary.gen && D.lang[baseLang(mp.summary.gen)]) ? mp.summary.gen : S.lang;
    if (!M.lang(lang)) return {};
    const clim = mp.climate || S.climate || 'temperate';
    const towns = townsFromLog(mp);
    applyQuota(lang, clim);
    const [res] = M.assign(towns, { lang, seed: S.seed, real: realSet(lang), climate: clim, year: S.mapYear || 1850, rules: S.mapRules || 's61' });
    const out = {};
    mp.towns.forEach((t, i) => { const r = res[i]; out[t.id] = r && r.new ? { name: u(r.new), parts: partsOf(r.info), shape: r.info && r.info.shape } : null; });
    return out;
  }
  function renderMap(el) {
    const mp = S.imported || D.map;
    const picker = `<p class="small"><label class="pick">Game log <input type="file" id="logFile" accept=".txt,.log,.gz"></label> <span class="muted">the NAME lines of the last map load (stdout.txt or an archived .log.gz of .cache/logs)</span>${S.imported ? ' <button class="btn small" id="clearImport">Clear the import</button>' : ''}</p>`;
    if (!mp || !mp.towns || !mp.towns.length) { el.innerHTML = picker + '<p class="muted">No map yet: pick a game log above, or export one into data.js: <code>uv run plans/square_organic_towns/names/export_names.py --session live</code></p>'; return; }
    const sm = mp.summary || {};
    const lab = mapLabNames(mp);
    el.innerHTML = picker + `<p class="muted">Seed text <b>${esc(mp.seedText || '-')}</b> · ${mp.towns.length} towns · list ${esc(sm.list || '-')} · generator ${esc(sm.gen || '-')} · rivers ${esc(sm.rivers || '-')} · lakes ${esc(sm.lakes || '-')} · from <code>${esc(mp.session || mp.log)}</code>. ` +
      `Tags are the log's top six (weight × specificity); <b>Load site</b> turns them back into weights. <b>Lab now</b>: the same towns through the lab's whole-map plan with your edits (lab seed; the game's map seed is not in the log). <b>Whole map (plan)</b> with the map "imported log" shows them on a map with the Q7 numbers.</p>` +
      `<div class="tablebox"><table class="maptable"><thead><tr><th>Game list → generated</th><th>Parts</th><th>Tags</th><th>Water</th><th>Dialect</th><th>Score</th><th>Lab now</th><th></th></tr></thead><tbody>` +
      mp.towns.map((t, i) => `<tr><td><span class="muted">${esc(t.old)}</span> → <b>${esc(t.new)}</b>${t.character ? ' <span class="pill">character</span>' : ''}</td>` +
        `<td>${esc(t.parts.filter(Boolean).join(' + '))}<br><span class="muted small">feature ${esc(t.feature)}</span></td>` +
        `<td>${t.tags.map(p => `<span class="pill">${esc(p[0])} ${f2(p[1])}</span>`).join(' ')}</td>` +
        `<td>${esc([t.river ? 'river ' + t.river : '', t.lake ? 'lake ' + t.lake : ''].filter(Boolean).join(', ') || '-')}<br><span class="muted small">${esc(t.read || '')}</span></td>` +
        `<td>${esc(t.dialect || '-')}</td><td>${f2(t.score)}</td>` +
        `<td>${lab[t.id] ? `<b>${esc(lab[t.id].name)}</b><br><span class="muted small">${esc(lab[t.id].parts.join(' + '))} · ${esc(lab[t.id].shape || '-')}</span>` : '-'}</td>` +
        `<td><button class="btn small" data-loadtown="${i}">Load site</button></td></tr>`).join('') + '</tbody></table></div>';
  }
  function loadTown(i) {
    const mp = S.imported || D.map;
    const t = mp.towns[i];
    const site = {};
    let ch = false;
    for (const [k, v] of t.tags) {
      if (k === 'character') { ch = true; continue; }
      site[k] = Math.round(Math.min(1, v / (M.SPEC[k] || 1)) * 100) / 100;
    }
    S.site = site; S.character = ch || t.character; S.preset = null;
    const g = mp.summary && mp.summary.gen;
    if (g && D.lang[baseLang(g)]) S.lang = g;
    if (t.dialect) S.dialect = t.dialect;
    S.view = 'all';
    rebuild(); all();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  // morpheme lists
  function origText(lang, kind) { return D.lang[baseLang(lang)][kind] || ''; }
  function curText(lang, kind) { const e = (S.edits[baseLang(lang)] || {})[kind]; return e != null ? e : origText(lang, kind); }
  function setText(lang, kind, txt) {
    const bl = baseLang(lang);
    S.edits[bl] = S.edits[bl] || {};
    if (txt === origText(lang, kind)) delete S.edits[bl][kind]; else S.edits[bl][kind] = txt;
    if (!Object.keys(S.edits[bl]).length) delete S.edits[bl];
    rebuild(); save(); renderSite(); renderResults();
  }
  function renderLists(el) {
    const lang = S.lang, kind = S.listKind;
    const lines = curText(lang, kind).split('\n').filter(l => l.trim() !== '');
    const orig = new Set(origText(lang, kind).split('\n').map(l => l.trim()).filter(Boolean));
    const L = M.lang(lang), x = M.expandSite(siteW());
    const parse = kind === 'spec' ? M.parseSpec : (kind === 'gen' ? M.parseGen : M.parseAffix);
    const rows = lines.map((line, i) => {
      const toks = b(line).match(/[^ \t\r]+/g) || [];
      const e = toks.length ? parse(toks, !!L.script) : null;
      const [fit, bt] = e ? M.fit(e, x) : [0, null];
      return { i, line, e, fit, bt, changed: !orig.has(line.trim()) };
    });
    const flt = (S.listFilter || '').toLowerCase();
    let shown = rows.filter(r => !flt || r.line.toLowerCase().indexOf(flt) >= 0);
    if (S.listSort === 'fit') shown = shown.slice().sort((a, c) => c.fit - a.fit || a.i - c.i);
    const edited = !!((S.edits[baseLang(lang)] || {})[kind]);
    const syntax = { spec: 'stem tag tag:weight @group * =class +p +c ~gender ("Ash ash", "Brad vale:.6 plain:.5 @saxon")',
      gen: '-suffix, _Word after, Word_ before, Pre^ joined prefix, Pre- hyphen prefix, then tags ("-ford ford river:.5 =cross")',
      affix: '%s the name, %l lower-case, %r river, %k lake, %p saint; "_" is a space ("%s-on-Sea coast sandy:.6")' }[kind];
    el.innerHTML = `<div class="listbar"><div class="seg" role="group" aria-label="List">` +
      ['spec', 'gen', 'affix'].map(k => `<button data-listkind="${k}" aria-pressed="${k === kind}">${{ spec: 'Stems', gen: 'Generics', affix: 'Affixes' }[k]} (${curText(lang, k).split('\n').filter(l => l.trim()).length})</button>`).join('') +
      `</div><input type="search" id="listFilter" placeholder="Filter" value="${esc(S.listFilter)}" aria-label="Filter lines">` +
      `<label class="pick">Sort <select id="listSort">${opt('fit', 'by fit to this site', S.listSort === 'fit')}${opt('file', 'file order', S.listSort === 'file')}</select></label>` +
      `<span class="spacer"></span>${edited ? '<span class="pill warn">edited</span> <button class="btn small" id="listRevert">Revert this list</button>' : ''}` +
      `<button class="btn small" id="listRaw">Edit as text</button></div>` +
      `<p class="muted small">${esc(LANG_NAMES[lang])} · ot_placename_lang.lua <code>${kind}</code> · syntax: ${esc(syntax)}. Edit a line and press Enter (or leave the field); the names update. Lines you changed or added are marked.</p>` +
      `<div class="addrow"><input id="addLine" placeholder="New line, e.g. ${kind === 'spec' ? 'Heron lake:.6 marsh:.5' : kind === 'gen' ? '-heron lake:.5' : '%s-by-the-Lake lake'}" aria-label="New line"><button class="btn small" id="addBtn">Add</button></div>` +
      `<div class="tablebox"><table class="listtable"><thead><tr><th>Fit</th><th>Line</th><th>Parsed</th><th></th></tr></thead><tbody>` +
      shown.map(r => `<tr class="${r.changed ? 'chg' : ''}"><td class="num">${r.fit > 0 ? f2(r.fit) : `<span class="muted">${f2(r.fit)}</span>`}</td>` +
        `<td><input class="lineedit" data-line="${r.i}" value="${esc(r.line)}" aria-label="Line ${r.i + 1}"></td>` +
        `<td class="small">${r.e ? entryLine(r.e) : ''}</td><td><button class="ic" data-delline="${r.i}" title="Remove">✕</button></td></tr>`).join('') +
      `</tbody></table></div>` +
      `<p class="muted small">Dialects (${esc(LANG_NAMES[lang])}): ${(L.dialects || []).map(d => `<b>${esc(u(d[0]))}</b> weight ${d[1]} → ${esc(Object.entries(d[2] || {}).map(([k, v]) => u(k) + ' ×' + v).join(', ') || 'neutral')}`).join(' · ') || 'none'}</p>`;
  }
  function listLines() { return curText(S.lang, S.listKind).split('\n').filter(l => l.trim() !== ''); }

  function renderConsts(el) {
    const C0 = D.pn.consts;
    const groups = [
      ['Scoring', ['SPEC_K', 'PAIR_BONUS', 'USE_GEN', 'USE_SPEC', 'JITTER', 'ANY', 'PERS_K', 'RARE_ON', 'RARE_OFF']],
      ['Affixes', ['AFFIX_COST', 'AFFIX_COST_CH', 'USE_AFFIX']],
      ['Search and length', ['TOP_SPEC', 'TOP_GEN', 'WIDE_SPEC', 'WIDE_GEN', 'MAX_BASE', 'MAX_FULL', 'MAX_KANJI']],
      ['Map (not used by the lab\'s 50-name runs)', ['RIVER_LINK_M', 'RIVER_DEG', 'LAKE_LINK_M', 'TWIN_MAX_M', 'TWIN_RATIO', 'FEAT_PER', 'FEAT_CAP', 'BORROW_P', 'BORDER_M']],
      ['Shapes (assign: the map\'s plan, NEXT_PHASE_BRIEF 53)', ['SHAPE_SLACK', 'SHAPE_OVER', 'QUIET_SHARE', 'QUIET_PEN', 'MAX_TOKENS', 'MAX_IDEAS', 'FEAT_BONUS', 'FEAT_FIRST', 'DIALECT_PEN']],
    ];
    const row = (k, v0, cur, attr) => `<tr${cur !== v0 ? ' class="chg"' : ''}><th>${esc(k)}</th><td><input type="number" step="any" ${attr}="${esc(k)}" value="${cur}"></td><td class="muted">${v0}</td></tr>`;
    el.innerHTML = `<p class="muted small">ot_placename constants (M.*) and tag specificity (M.SPEC). Changes apply to every mode at once and go into the export.</p><div class="cgrid">` +
      groups.map(([g, ks]) => `<section><h3>${esc(g)}</h3><table class="ctable"><tr><th></th><th>Value</th><th>Mod</th></tr>${ks.filter(k => k in C0).map(k => row(k, C0[k], M.C[k], 'data-const')).join('')}</table></section>`).join('') +
      `<section><h3>Tag specificity (SPEC)</h3><table class="ctable"><tr><th></th><th>Value</th><th>Mod</th></tr>${D.pn.TAGS.filter(t => t !== 'any').map(t => row(t, D.pn.SPEC[t], M.SPEC[t], 'data-spec')).join('')}</table></section></div>` +
      `<button class="btn" id="constReset">Reset constants and specificity</button>`;
  }
  function renderOpts(el) {
    const id = ideas(S.lang), bl = baseLang(S.lang);
    el.innerHTML = `<div class="cgrid"><section><h3>Real-name remix</h3>` +
      `<label class="pick">Chain order <input type="number" min="1" max="5" id="optOrder" value="${S.opt.order}"></label><br>` +
      `<label class="pick">Tag bias <input type="range" min="0" max="1" step="0.05" id="optBias" value="${S.opt.bias}"> <span>${Math.round(S.opt.bias * 100)}%</span></label>` +
      `<p class="muted small">Share of names that start with a fitting stem or end with a fitting generic (half each); the rest come from the chain alone.</p>` +
      `<label class="pick"><input type="checkbox" id="optSingle"${S.opt.singleWords ? ' checked' : ''}> Train on one-word names only</label>` +
      `<p class="muted small">Training set: ${((D.towns[S.lang] || {}).names || []).length} names from ${esc(((D.towns[S.lang] || {}).sources || []).join(', ') || '-')}.</p></section>` +
      `<section><h3>Old forms</h3><label class="pick">Old prefix / suffix share <input type="range" min="0" max="1" step="0.05" id="optOld" value="${S.opt.oldShare}"> <span>${Math.round(S.opt.oldShare * 100)}%</span></label>` +
      `<label class="pick"><input type="checkbox" id="optSpell"${S.opt.spelling ? ' checked' : ''}> Old spellings</label>` +
      `<label class="pick">Groups <input id="optGroups" value="${esc(id.oldGroups)}" placeholder="celtic norse"></label>` +
      `<p class="muted small">Spelling rules (${esc(LANG_NAMES[S.lang])}): <code>regex =&gt; replacement</code> per line.</p><textarea id="optOldRules" rows="10" spellcheck="false">${esc(id.old)}</textarea></section>` +
      `<section><h3>Descriptive</h3><p class="muted small">Extra terrain / colour words (${esc(LANG_NAMES[S.lang])}) in the stem syntax; joined with the inventory's terrain generics.</p>` +
      `<textarea id="optAdj" rows="12" spellcheck="false">${esc(id.adj)}</textarea></section></div>` +
      `${S.ideas[bl] ? '<button class="btn" id="ideasReset">Revert the idea lists of this language</button>' : ''}`;
  }
  function renderRated(el) {
    const pins = Object.values(S.pinned), rated = Object.values(S.ratings);
    const item = (r, kind) => `<li><b>${esc(r.name)}</b> <span class="muted small">${esc(MODE[r.mode] ? MODE[r.mode].name : r.mode)} · ${esc(r.lang)} · ${esc((r.parts || []).join(' + '))} · ${esc((r.site || []).join(', '))}</span>` +
      `${kind === 'r' ? ` ${r.r > 0 ? '👍' : '👎'}` : ''} <button class="ic" data-un${kind}="${esc(r.key)}" title="Remove">✕</button></li>`;
    el.innerHTML = `<div class="cgrid"><section><h3>Pinned (${pins.length})</h3><ul class="plain">${pins.map(r => item(r, 'p')).join('') || '<li class="muted">Pin names with 📌.</li>'}</ul></section>` +
      `<section><h3>Rated (${rated.length})</h3><ul class="plain">${rated.sort((a, c) => c.r - a.r).map(r => item(r, 'r')).join('') || '<li class="muted">Rate names with 👍 / 👎.</li>'}</ul></section>` +
      `<section><h3>Notes</h3><textarea id="notes" rows="10" placeholder="What should change? (goes into the export)">${esc(S.notes)}</textarea></section></div>`;
  }
  function renderStop(el) {
    const SL = (D.stop && D.stop.LANG) || {};
    const keys = Object.keys(SL);
    const k = SL[S.lang] ? S.lang : (SL[baseLang(S.lang)] ? baseLang(S.lang) : keys[0]);
    const L = SL[k] || {};
    const block = (title, obj) => obj ? `<h4>${esc(title)}</h4><table class="ctable stoptable">${Object.entries(obj).map(([th, v]) =>
      `<tr><th>${esc(th)}</th><td>${(Array.isArray(v) ? v : (typeof v === 'object' ? Object.values(v) : [v])).map(x => `<span class="pill">${esc(Array.isArray(x) ? x.join(' ') : x)}</span>`).join(' ')}</td></tr>`).join('')}</table>` : '';
    el.innerHTML = `<p class="muted small">ot_stopname.LANG (read-only): the parts of the composed stop names per theme. Language: <b>${esc(k)}</b> (lists: ${keys.map(esc).join(', ')}).</p>` +
      block('Generics', L.gens) + block('Stand-alone names', L.solos) + block('Specific parts', L.specs) +
      block('Other parts', Object.fromEntries(Object.entries(L).filter(([kk, v]) => ['gens', 'solos', 'specs', 'join', 'own'].indexOf(kk) < 0 && v && typeof v === 'object')));
  }
  let PORT = null;
  function renderPort(el) {
    if (!PORT) PORT = window.PortCheck.run(D, NG);
    el.innerHTML = `<p>${PORT.ok === PORT.n && !PORT.parse.length ? '<span class="pill ok">match</span>' : '<span class="pill warn">differs</span>'} The JS port gives <b>${PORT.ok} / ${PORT.n}</b> of Lua's names (ot_placename.assign on synthetic maps: every preset twice, character towns, river chains, lakes, twins, the map's name shapes (planShapes, NEXT_PHASE_BRIEF 53), towns with the map survey's cues, a kept town, the word budget and tag rarity on; export_names.py runs them in Lua). Parser: ${PORT.parse.length ? PORT.parse.length + ' entries differ' : 'every inventory line parses the same'}. Unedited data and constants.</p>` +
      `<div class="tablebox"><table><thead><tr><th>Language</th><th>Match</th><th>First difference</th></tr></thead><tbody>${PORT.langs.map(l => `<tr><td>${esc(l.lang)}</td><td>${l.ok} / ${l.n}</td><td class="small">${l.bad.length ? esc(JSON.stringify(l.bad[0])) : '-'}</td></tr>`).join('')}</tbody></table></div>` +
      `<h4>Where the lab differs from the game</h4><ul class="small">
      <li>Sites come from the site builder (weights per tag); the mod measures them (ot_placename.read / siteTags, not ported).</li>
      <li>"Generate" names n towns of the same site on one imaginary map (or each alone): dialect areas over a 7-wide grid, one river / lake name per five towns; the game links rivers by distance and axis (riverSystems, ported and checked here) and orders towns by distinctiveness.</li>
      <li>The site-builder modes name each town of the run alone (any shape, no twins, the site builder's one site); <b>Whole map (plan)</b> runs assign itself: a synthetic map of mixed sites (test_shapegates' maps) or an imported log's sites, with the shape plan, the settlement layers, twins and the feature budget.</li>
      <li>Affix probability is a lab gate in front of the mod's affix rule (100% = the mod's behaviour).</li>
      <li>Districts and Works (related / works) are not ported.</li></ul>`;
  }
  function buildExport() {
    const C0 = D.pn.consts;
    const consts = {}, spec = {};
    for (const k in S.consts) if (S.consts[k] !== C0[k]) consts[k] = { mod: C0[k], lab: S.consts[k] };
    for (const k in S.spec) if (S.spec[k] !== D.pn.SPEC[k]) spec[k] = { mod: D.pn.SPEC[k], lab: S.spec[k] };
    const listEdits = {};
    for (const l in S.edits) for (const kind in S.edits[l]) {
      const a = new Set(D.lang[l][kind].split('\n').map(s => s.trim()).filter(Boolean));
      const bb = new Set(S.edits[l][kind].split('\n').map(s => s.trim()).filter(Boolean));
      listEdits[l] = listEdits[l] || {};
      listEdits[l][kind] = { added: [...bb].filter(x => !a.has(x)), removed: [...a].filter(x => !bb.has(x)) };
    }
    const ideaEdits = {};
    for (const l in S.ideas) ideaEdits[l] = S.ideas[l];
    const strip = r => ({ name: r.name, mode: r.mode, lang: r.lang, parts: r.parts, site: r.site, character: r.character, shape: r.shape || null,
      layer: r.layer || null, climate: r.climate || null, ...(r.r ? { rating: r.r > 0 ? 'up' : 'down' } : {}) });
    return {
      kind: 'organic-towns-name-lab', version: 1, exported: new Date().toISOString(), data: { built: D.built, src: D.src },
      request: 'Implement these name-generation settings in ot_placename / ot_placename_lang.',
      settings: { lang: S.lang, mode: S.mode, view: S.view, seed: S.seed, dialect: S.dialect, affixProbability: S.affixP,
        character: S.character, sharedMap: S.shared, preset: S.preset, site: siteW() },
      modeOptions: S.opt, constants: consts, specificity: spec, listEdits, ideaEdits,
      ratings: Object.values(S.ratings).map(strip), pinned: Object.values(S.pinned).map(strip), notes: S.notes,
      // (NEXT_PHASE_BRIEF 53 Part B, review Q8) the whole-map ratings, the shape A/B votes, everything per shape, the targets
      mapRatings: Object.values(S.mapRatings || {}), abTests: S.ab || [], byShape: shapeSummary(), shapeTargets: S.quotaEdit || {},
      importedLog: S.imported ? { seedText: S.imported.seedText, towns: S.imported.towns.length, climate: S.imported.climate } : null,
    };
  }
  function renderExport(el) {
    const j = JSON.stringify(buildExport(), null, 1);
    el.innerHTML = `<p class="muted small">Everything you changed: settings, constants, list edits (added / removed lines per list), idea lists, ratings, pins, notes. <b>Copy and download</b> puts it on the clipboard and saves <code>name-lab-export.json</code>; paste it to Claude with "implement this".</p>` +
      `<button class="btn primary" id="exportBtn2">Copy and download</button><pre class="json">${esc(j)}</pre>`;
  }
  function doExport() {
    const j = JSON.stringify(buildExport(), null, 1);
    let copied = false;
    const done = () => toast(copied ? 'Copied to the clipboard and downloaded' : 'Downloaded (clipboard blocked)');
    try {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([j], { type: 'application/json' }));
      a.download = 'name-lab-export.json'; document.body.appendChild(a); a.click(); a.remove();
    } catch (e) { /* ignore */ }
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(j).then(() => { copied = true; done(); }, done);
      else done();
    } catch (e) { done(); }
  }
  function toast(t) { const el = $('#toast'); el.textContent = t; el.hidden = false; clearTimeout(el._t); el._t = setTimeout(() => { el.hidden = true; }, 2600); }

  // ------------------------------------------------------------------ events
  function all() { renderControls(); renderSite(); renderResults(); renderTabs(); renderHead(); save(); }
  function renderHead() {
    const nEd = Object.keys(S.edits).length + Object.keys(S.consts).length + Object.keys(S.spec).length;
    $('#stateinfo').textContent = `${Object.keys(S.pinned).length} pinned · ${Object.keys(S.ratings).length} rated · ${Object.keys(S.mapRatings || {}).length} maps rated · ${(S.ab || []).length} A/B votes${nEd ? ' · edits active' : ''}`;
  }
  document.addEventListener('change', ev => {
    const t = ev.target;
    if (t.id === 'lang') { S.lang = t.value; rebuild(); all(); }
    else if (t.id === 'dialect') { S.dialect = t.value; renderResults(); save(); }
    else if (t.id === 'seed') { S.seed = Math.max(1, parseInt(t.value, 10) || 1); renderResults(); renderTabs(); save(); }
    else if (t.id === 'character') { S.character = t.checked; renderSite(); renderResults(); save(); }
    else if (t.id === 'budget') { S.budget = t.checked; renderResults(); save(); }
    else if (t.id === 'climate') { S.climate = t.value; renderResults(); save(); }
    else if (t.id === 'shared') { S.shared = t.value === '1'; renderResults(); save(); }
    else if (t.id === 'count') { S.opt.count = Math.max(5, Math.min(200, parseInt(t.value, 10) || 50)); renderResults(); save(); }
    else if (t.id === 'mapPreset') { if (t.value === 'log') S.mapSrc = 'log'; else { S.mapSrc = 'synthetic'; S.mapPreset = t.value; } AB = null; renderResults(); save(); }
    else if (t.id === 'mapRules') { S.mapRules = t.value === 's53' ? 's53' : (t.value === 's60' ? 's60' : 's61'); AB = null; renderResults(); save(); }
    else if (t.id === 'mapYear') { S.mapYear = Math.max(1800, Math.min(2050, parseInt(t.value, 10) || 1850)); renderResults(); save(); }
    else if (t.dataset.quota) {
      const v = parseFloat(t.value);
      if (!isNaN(v) && MAPRUN) {
        const k = quotaKey(MAPRUN.lang, MAPRUN.clim);
        S.quotaEdit = S.quotaEdit || {}; S.quotaEdit[k] = S.quotaEdit[k] || {};
        S.quotaEdit[k][t.dataset.quota] = Math.max(0, Math.min(1, v));
        renderResults(); renderHead(); save();
      }
    } else if (t.id === 'logFile' && t.files && t.files[0]) {
      const f = t.files[0];
      const done = text => {
        const mp = parseLog(text);
        if (!mp) { toast('No NAME lines in ' + f.name); return; }
        S.imported = mp; S.mapSrc = 'log'; S.mode = 'map'; S.view = 'grid'; AB = null;
        toast(`${mp.towns.length} towns from ${f.name}`); all();
      };
      if (/\.gz$/i.test(f.name) && typeof DecompressionStream === 'function') {
        new Response(f.stream().pipeThrough(new DecompressionStream('gzip'))).text().then(done, e => toast('Could not read: ' + e.message));
      } else f.text().then(done, e => toast('Could not read: ' + e.message));
    }
    else if (t.dataset.tag) {
      if (t.checked) S.site[t.dataset.tag] = 0.8; else delete S.site[t.dataset.tag];
      S.preset = null; renderSite(); renderResults(); if (S.tab === 'lists') renderTabs(); save();
    } else if (t.classList.contains('lineedit')) {
      const ls = listLines(); const i = +t.dataset.line;
      if (t.value.trim() === '') ls.splice(i, 1); else ls[i] = t.value;
      setText(S.lang, S.listKind, ls.join('\n') + '\n'); renderTabs();
    } else if (t.id === 'listSort') { S.listSort = t.value; renderTabs(); save(); }
    else if (t.dataset.const || t.dataset.spec) {
      const v = parseFloat(t.value);
      if (!isNaN(v)) {
        if (t.dataset.const) { if (v === D.pn.consts[t.dataset.const]) delete S.consts[t.dataset.const]; else S.consts[t.dataset.const] = v; }
        else { if (v === D.pn.SPEC[t.dataset.spec]) delete S.spec[t.dataset.spec]; else S.spec[t.dataset.spec] = v; }
        rebuild(); renderSite(); renderResults(); renderTabs(); renderHead(); save();
      }
    } else if (t.id === 'optOrder') { S.opt.order = Math.max(1, Math.min(5, parseInt(t.value, 10) || 3)); renderResults(); save(); }
    else if (t.id === 'optSingle') { S.opt.singleWords = t.checked; renderResults(); save(); }
    else if (t.id === 'optSpell') { S.opt.spelling = t.checked; renderResults(); save(); }
    else if (t.id === 'optOldRules' || t.id === 'optAdj' || t.id === 'optGroups') {
      const bl = baseLang(S.lang); S.ideas[bl] = S.ideas[bl] || {};
      S.ideas[bl][{ optOldRules: 'old', optAdj: 'adj', optGroups: 'oldGroups' }[t.id]] = t.value;
      renderResults(); renderTabs(); save();
    } else if (t.id === 'notes') { S.notes = t.value; save(); }
  });
  document.addEventListener('input', ev => {
    const t = ev.target;
    if (t.id === 'affixP') { S.affixP = +t.value; $('#affixPv').textContent = Math.round(S.affixP * 100) + '%'; debounce(renderResults); save(); }
    else if (t.dataset.tagw) { S.site[t.dataset.tagw] = +t.value; S.preset = null; t.nextElementSibling.textContent = (+t.value).toFixed(2); debounce(() => { renderResults(); $('#ranked').innerHTML = M.ranked(siteW()).slice(0, 8).map(r => `<span class="pill">${esc(r[0])} ${f2(r[1])}</span>`).join(' '); }); save(); }
    else if (t.id === 'listFilter') { S.listFilter = t.value; debounce(() => { renderTabs(); const f = $('#listFilter'); f.focus(); f.setSelectionRange(f.value.length, f.value.length); }, 200); }
    else if (t.id === 'optBias') { S.opt.bias = +t.value; t.nextElementSibling.textContent = Math.round(S.opt.bias * 100) + '%'; debounce(renderResults); save(); }
    else if (t.id === 'optOld') { S.opt.oldShare = +t.value; t.nextElementSibling.textContent = Math.round(S.opt.oldShare * 100) + '%'; debounce(renderResults); save(); }
    else if (t.id === 'notes') { S.notes = t.value; save(); renderHead(); }
  });
  let debT = null;
  function debounce(f, ms) { clearTimeout(debT); debT = setTimeout(f, ms || 120); }
  document.addEventListener('keydown', ev => {
    if (ev.key === 'Enter' && ev.target.classList.contains('lineedit')) ev.target.blur();
    if (ev.key === 'Enter' && ev.target.id === 'addLine') $('#addBtn').click();
  });
  document.addEventListener('click', ev => {
    const t = ev.target.closest('button, .ncard');
    if (!t) return;
    if (t.matches('#modes button')) {
      if (t.dataset.mode === 'all') S.view = 'all'; else { S.view = 'grid'; S.mode = t.dataset.mode; }
      LOCK = null; renderControls(); renderResults(); save();
    } else if (t.id === 'gen') { renderResults(); }
    else if (t.id === 'dice') { S.seed = (S.seed % 99999) + 1; $('#seed').value = S.seed; renderResults(); if (S.tab === 'map') renderTabs(); save(); }
    else if (t.dataset.preset) { S.site = Object.assign({}, D.presets[t.dataset.preset]); for (const k in S.site) if (S.site[k] < 0.2) delete S.site[k]; S.preset = t.dataset.preset; renderSite(); renderResults(); if (S.tab === 'lists') renderTabs(); save(); }
    else if (t.id === 'clearSite') { S.site = {}; S.preset = null; renderSite(); renderResults(); save(); }
    else if (t.dataset.act) {
      const c = t.closest('.ncard'); const r = IDX[+c.dataset.idx]; if (!r || !r.name) return;
      const k = rkey(r);
      const rec = { key: k, name: r.name, mode: r.mode, lang: S.lang, parts: r.parts || [], site: M.ranked(siteW()).slice(0, 6).map(x => x[0] + ':' + (S.site[x[0]] != null ? (+S.site[x[0]]).toFixed(2) : '1')), character: S.character,
        // (NEXT_PHASE_BRIEF 53 Part B: every rating keeps the name's shape and layer; the export adds them up per shape)
        shape: r.info && r.info.shape ? r.info.shape : null, layer: r.info && r.info.layer ? r.info.layer : null, climate: S.climate };
      if (r.mode === 'map' && MAPRUN) rec.site = M.ranked(MAPRUN.towns[r.ti].w).slice(0, 6).map(x => x[0] + ':' + f2(MAPRUN.towns[r.ti].w[x[0]]));
      if (t.dataset.act === 'pin') { if (S.pinned[k]) delete S.pinned[k]; else S.pinned[k] = rec; }
      else { const v = t.dataset.act === 'up' ? 1 : -1; if (S.ratings[k] && S.ratings[k].r === v) delete S.ratings[k]; else S.ratings[k] = Object.assign(rec, { r: v }); }
      c.outerHTML = card(r, +c.dataset.idx, false);
      renderHead(); if (S.tab === 'rated') renderTabs(); save();
      ev.stopPropagation();
    } else if (t.classList.contains('ncard')) {
      const i = +t.dataset.idx; LOCK = LOCK === i ? null : i; showWhy(IDX[i] || null);
      $$('.ncard.sel').forEach(x => x.classList.remove('sel')); if (LOCK != null) t.classList.add('sel');
    } else if (t.id === 'unlock') { LOCK = null; $$('.ncard.sel').forEach(x => x.classList.remove('sel')); showWhy(null); }
    else if (t.dataset.tab) { S.tab = t.dataset.tab; renderTabs(); save(); }
    else if (t.dataset.loadtown != null) loadTown(+t.dataset.loadtown);
    else if (t.dataset.listkind) { S.listKind = t.dataset.listkind; renderTabs(); save(); }
    else if (t.dataset.delline != null) { const ls = listLines(); ls.splice(+t.dataset.delline, 1); setText(S.lang, S.listKind, ls.join('\n') + '\n'); renderTabs(); renderHead(); }
    else if (t.id === 'addBtn') { const v = $('#addLine').value.trim(); if (v) { const ls = listLines(); ls.unshift(v); setText(S.lang, S.listKind, ls.join('\n') + '\n'); renderTabs(); renderHead(); } }
    else if (t.id === 'listRevert') { setText(S.lang, S.listKind, origText(S.lang, S.listKind)); renderTabs(); renderHead(); }
    else if (t.id === 'listRaw') {
      const el = $('#tabbody');
      el.innerHTML = `<p class="muted small">${esc(LANG_NAMES[S.lang])} · <code>${S.listKind}</code> as text (one entry per line). <button class="btn small" id="rawApply">Apply</button> <button class="btn small" id="rawCancel">Back to the table</button></p><textarea id="rawText" rows="28" spellcheck="false">${esc(curText(S.lang, S.listKind))}</textarea>`;
    } else if (t.id === 'rawApply') { setText(S.lang, S.listKind, $('#rawText').value); renderTabs(); renderHead(); }
    else if (t.id === 'rawCancel') renderTabs();
    else if (t.id === 'constReset') { S.consts = {}; S.spec = {}; rebuild(); all(); }
    else if (t.id === 'ideasReset') { delete S.ideas[baseLang(S.lang)]; renderResults(); renderTabs(); save(); }
    else if (t.dataset.unp) { delete S.pinned[t.dataset.unp]; renderTabs(); renderResults(); renderHead(); save(); }
    else if (t.dataset.unr) { delete S.ratings[t.dataset.unr]; renderTabs(); renderResults(); renderHead(); save(); }
    else if (t.id === 'exportBtn' || t.id === 'exportBtn2') doExport();
    else if (t.dataset.maprate && MAPRUN) {
      const R = MAPRUN;
      S.mapRatings = S.mapRatings || {};
      S.mapRatings[R.key] = { key: R.key, rating: +t.dataset.maprate, lang: R.lang, climate: R.clim, src: R.src, seed: S.seed,
        towns: R.res.length, shapes: Object.assign({}, R.st.shapes.used), layers: Object.assign({}, R.st.shapes.layers || {}),
        names: R.res.map(r => u(r.new)), shapeTargets: (S.quotaEdit || {})[quotaKey(R.lang, R.clim)] || null };
      renderResults(); renderHead(); save();
    } else if (t.id === 'abNext' && MAPRUN) { abNext(MAPRUN); renderResults(); save(); }
    else if (t.dataset.abpick && AB && AB.t) {
      S.ab = S.ab || [];
      S.ab.push({ lang: MAPRUN.lang, climate: MAPRUN.clim, site: AB.t.site, A: AB.t.A, B: AB.t.B, pick: t.dataset.abpick });
      abNext(MAPRUN); renderResults(); renderHead(); save();
    } else if (t.id === 'clearImport') { S.imported = null; S.mapSrc = 'synthetic'; all(); }
    else if (t.id === 'reset') {
      if (confirm('Reset the lab: settings, edited lists, constants, ratings, pins and notes?')) {
        try { localStorage.removeItem(KEY); } catch (e) { /* ignore */ }
        S = defaults(); LOCK = null; rebuild(); all();
      }
    }
  });
  document.addEventListener('mouseover', ev => {
    if (LOCK != null) return;
    const c = ev.target.closest && ev.target.closest('.ncard');
    if (c && IDX[+c.dataset.idx]) showWhy(IDX[+c.dataset.idx]);
  });

  // header
  $('#builtinfo').innerHTML = `Data ${esc(D.built)} from <code>ot_placename.lua</code> ${esc(D.src['ot_placename.lua'].sha)} · <code>ot_placename_lang.lua</code> ${esc(D.src['ot_placename_lang.lua'].sha)}`;
  setTimeout(() => {
    try {
      PORT = window.PortCheck.run(D, NG);
      const ok = PORT.ok === PORT.n && !PORT.parse.length;
      $('#portbadge').innerHTML = `<button class="pill ${ok ? 'ok' : 'warn'}" data-tab="port" title="Port check">${ok ? 'JS port = Lua' : 'port differs'} ${PORT.ok}/${PORT.n}</button>`;
      if (S.tab === 'port') renderTabs();
    } catch (e) { $('#portbadge').textContent = 'port check failed: ' + e.message; }
  }, 30);
  all();
})();
