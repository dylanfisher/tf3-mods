// Organic Towns Name lab: a TypeScript port of mods/square_organic_towns/content/organic_towns/ot_placename.lua
// (the morpheme generator) and ot_rng.lua (the hash RNG). Hand-ported; the old disk page's
// plans/square_organic_towns/names/gen.js is generated from this file (gen_js.mjs, since NEXT_PHASE_BRIEF 60);
// the data comes from plans/square_organic_towns/names/data.json (export_names.py). Verified against Lua's own runs by
// `node plans/square_organic_towns/names/check_port.mjs` (and the lab's Port check tab): run it after every change
// here or to the mod's Lua. The port mirrors dynamically typed Lua, so values are typed `any`; erasable TypeScript
// only, so Node runs this file directly.
//
// Strings: every string inside the port is a "byte string" (one JS char per UTF-8 byte, b()), so Lua's byte-wise
// string functions (sub, #, patterns with \128-\255, the hash of a string) carry over unchanged. u() turns a result
// back into text for display.
//
// Ported 1:1: the parser (lang), expandSite, fit, sufJoin / elide / adjForm / sameWord / join, the blocklist,
// wellFormed, newCtx / take / free, regions / dialectAt, riverSystems / lakeSystems, riverName / lakeName, repeats,
// fillAffix, rankParts, family, nameTown, assign (with satellites), satellite; from 2026-10-14 (NEXT_PHASE_BRIEF 45,
// "Names from the map's shape") the map survey's cue tags (withCues, rankOf), the word budget and tag rarity of
// ot_namewords.lua (M.NW: keys / newBudget / check / allow / add / remove / rarity / applyRarity), whole-name affixes,
// the %t %m %M %b %B %D %E fields and featName. Not ported: read / siteTags and ot_mapshape (they need the game's
// terrain; the lab's site builder sets the weights, cue tags included, directly), related / works / stemOf.
// Additions that don't change a result: nameTown returns info.dbg (the scores and the runner-up candidates) and takes
// two lab hooks: t.noAffix (already in the Lua) and opts on the module (M.C: the constants, editable in the page).
// From 2026-10-14 (NEXT_PHASE_BRIEF 49) the climate of ot_climate.lua (data.js `climate`): the tag veto in rankParts and
// the affixes, the finished name's word check (within, river and lake names), assign's o.climate, st.misfit.
// NEXT_PHASE_BRIEF 50: dialect pairs (compatible, the +f / +w registers), roots and affix patterns in the word budget
// (rootIndex / extraKeys / attachExtra; the budget's neighbourhood rule: setTowns / hoodR2), the feature qualifier rule
// (featureUses / featureOk / featureTake), bare whole names. NEXT_PHASE_BRIEF 53 Part A: the map's shape plan
// (planShapes, featureGrants, twins, the dialect areas of regions / dialectAt, tokens / ideas, the shaped nameTown,
// shapeFields), with the plan's seeded draws (draw). NEXT_PHASE_BRIEF 53 Part B: settlement layers (oldness / layers /
// yearLayer, layerAdj), the climate shape tables (climateOf: shares, words, boost, veto, shared groups, saints, areas, the
// settler group), +x parts and their gender, civic names only on late towns away from confluences, the character kinds.
// NEXT_PHASE_BRIEF 60: the descriptive rules (o.rules "s60", default; "s53" the review's): opaque / flavor parts (+u, +p,
// +n) capped and gated (rankParts), quota60, quiet 10 %, flavor towns (planShapes), multi-word bonus, frames on a named
// feature, the +a / +e rule, siteWord and the NAMES shapes desc / opaque / flavor / multi fields.

// ---------------------------------------------------------------- bytes
function b(s?: any): any { s = s == null ? '' : String(s); try { return unescape(encodeURIComponent(s)); } catch (e: any) { return s; } }
function u(s?: any): any { if (s == null) return s; try { return decodeURIComponent(escape(s)); } catch (e: any) { return s; } }

// ---------------------------------------------------------------- ot_rng
const MOD = 2147483647, MUL = 48271;
const floor = Math.floor;
function lmod(a?: any, m?: any): any { const r = a % m; return r < 0 ? r + m : r; }  // Lua's floored %
function norm(v?: any): any { v = lmod(floor(v), MOD); if (v === 0) v = 1; return v; }
function mixNumber(h?: any, v?: any): any {
  let n = floor(v);
  if (n < 0) n = -n * 2 + 1; else n = n * 2;
  const lo = lmod(n, 65536), mid = lmod(floor(n / 65536), 65536), hi = lmod(floor(n / 4294967296), 65536);
  h = lmod(h * 31 + lo + 1, MOD);
  h = lmod(h * 31 + mid + 7, MOD);
  h = lmod(h * 31 + hi + 13, MOD);
  return lmod(h * MUL, MOD);
}
function mixString(h?: any, s?: any): any {
  for (let i = 0; i < s.length; i++) h = lmod(h * 31 + s.charCodeAt(i), MOD);
  return lmod(h * MUL, MOD);
}
function hash(...args: any[]): number {
  let h = 2166136;
  for (let i = 0; i < args.length; i++) {
    const v = args[i], t = typeof v;
    if (t === 'number') h = mixNumber(h, v);
    else if (t === 'string') h = mixString(h, v);
    else if (t === 'boolean') h = mixNumber(h, v ? 3 : 5);
    else h = mixNumber(h, 11);
  }
  h = norm(h);
  for (let k = 0; k < 3; k++) h = lmod(h * MUL, MOD);
  return norm(h);
}
function unit(...args: any[]): number { return (hash(...args) - 1) / (MOD - 1); }
const rng: any = { hash, unit };

// ---------------------------------------------------------------- module factory
function create(DATA?: any, opt?: any): any {
  opt = opt || {};
  const PN = DATA.pn;
  const M: any = {};
  M.C = Object.assign({}, PN.consts, opt.consts || {});
  const C = M.C;
  M.TAGS = PN.TAGS.slice();
  M.SPECIES = PN.SPECIES.slice();
  M.TAG_INDEX = {}; M.TAGS.forEach((t?: any, i?: any) => { M.TAG_INDEX[t] = i + 1; });
  M.PARENT = PN.PARENT; M.SPEC = Object.assign({}, PN.SPEC, opt.spec || {}); M.CONTRA = Object.assign({}, PN.CONTRA, opt.contra || {});
  M.BAD = [];

  // strings
  const UPu: any = { 'à': 'À', 'á': 'Á', 'â': 'Â', 'ä': 'Ä', 'å': 'Å', 'æ': 'Æ', 'ç': 'Ç', 'è': 'È', 'é': 'É', 'ê': 'Ê', 'í': 'Í',
    'ñ': 'Ñ', 'ó': 'Ó', 'ô': 'Ô', 'ö': 'Ö', 'ø': 'Ø', 'ú': 'Ú', 'ü': 'Ü', 'ō': 'Ō', 'ū': 'Ū' };
  const UP: any = {}, DOWN: any = {};
  for (const k in UPu) { UP[b(k)] = b(UPu[k]); DOWN[b(UPu[k])] = b(k); }
  function firstChar(s?: any): any {
    const c = s.charCodeAt(0);
    if (c >= 192) { const n = c >= 240 ? 4 : (c >= 224 ? 3 : 2); return [s.slice(0, n), s.slice(n)]; }
    return [s.slice(0, 1), s.slice(1)];
  }
  function asciiUpper(c?: any): any { return c.length === 1 && c.charCodeAt(0) < 128 ? c.toUpperCase() : c; }
  M.capFirst = function (s?: any): any { if (s === '') return s; const [c, rest] = firstChar(s); return (UP[c] || asciiUpper(c)) + rest; };
  M.lowerFirst = function (s?: any): any {
    if (s === '') return s; const [c, rest] = firstChar(s);
    if (c.length === 1) return (c.charCodeAt(0) < 128 ? c.toLowerCase() : c) + rest;
    return (DOWN[c] || c) + rest;
  };
  function lower(s?: any): any { return s.replace(/[A-Z]/g, (ch: any) => ch.toLowerCase()); }
  function lowerAll(s?: any): any { s = lower(s); return s.replace(/[\xc3\xc5][\x80-\xbf]/g, (ch: any) => DOWN[ch] || ch); }
  M.lowerAll = lowerAll;
  M.chars = function (s?: any): any { s = s == null ? '' : String(s); let n = 0; for (let i = 0; i < s.length; i++) { const c = s.charCodeAt(i); if (c < 128 || c > 191) n++; } return n; };
  function split(s?: any, sep?: any): any { if (typeof s !== 'string' || s === '') return []; return s.split(sep); }
  function blen(s?: any): any { return s.length; }

  // inventories
  function newEntry(text?: any): any { return { text: text, tl: [], flags: {} }; }
  M.newEntry = newEntry;
  function parseTags(toks?: any, i0?: any, e?: any): any {
    for (let i = i0 - 1; i < toks.length; i++) {
      const t = toks[i], c = t.slice(0, 1);
      if (c === '@') e.grp = t.slice(1);
      else if (t === '*') e.rare = true;
      else if (c === '=') e.cls = t.slice(1);
      else if (c === '+') e.flags[t.slice(1)] = true;
      else if (c === '~') e.gender = t.slice(1);
      // (NEXT_PHASE_BRIEF 61: ?tag[:min] an evocative name's gate, !fam an industry form's family)
      else if (c === '?') {
        e.gate = e.gate || [];
        const m = /^([A-Za-z_|0-9]+):?([0-9.]*)$/.exec(t.slice(1));
        if (m) e.gate.push({ min: m[2] === '' ? null : Number(m[2]), tags: m[1].split('|').filter((x: any) => x !== '') });
        else M.BAD.push(t);
      }
      else if (c === '!') e.fam = t.slice(1);
      else {
        const m = /^([A-Za-z_]+):?([0-9.]*)$/.exec(t);
        if (m && M.TAG_INDEX[m[1]]) {
          const w = m[2] === '' ? NaN : Number(m[2]);
          e.tl.push([m[1], isNaN(w) ? 1 : w]);
        } else M.BAD.push(t);
      }
    }
    const x: any = {};
    for (const p of e.tl) {
      const t = p[0], w = p[1];
      if ((x[t] || 0) < w) x[t] = w;
      const up = function (tag?: any, f?: any, depth?: any): any {
        for (const par of (M.PARENT[tag] || [])) {
          if ((x[par] || 0) < w * f) x[par] = w * f;
          if (depth < 3) up(par, f * 0.5, depth + 1);
        }
      };
      up(t, 0.5, 1);
    }
    e.x = [];
    for (const t of M.TAGS) if (x[t] !== undefined) e.x.push([t, x[t]]);
    let bt: any = null, bw = -1;
    for (const p of e.tl) if (p[1] > bw && p[0] !== 'any') { bt = p[0]; bw = p[1]; }
    e.main = bt;
  }
  M.parseTags = parseTags;
  function lines(s?: any): any {
    const out: any = [];
    for (const line of (s || '').split('\n')) {
      if (line === '') continue;
      const toks = line.match(/[^ \t\r]+/g) || [];
      if (toks.length > 0) out.push(toks);
    }
    return out;
  }
  M.lines = lines;
  function parseSpec(toks?: any, script?: any): any {
    const raw = toks[0]; let e: any;
    if (script) {
      const m = /^([^/]+)\/(.+)$/.exec(raw);
      e = newEntry(m ? m[1] : null); if (m) { e.k = m[1]; e.r = m[2]; } e.kind = 'stem';
    } else if (raw.indexOf('|') >= 0) {
      e = newEntry(raw); e.forms = split(raw, '|'); e.text = e.forms[0]; e.kind = 'adj';
    } else {
      e = newEntry(raw.replace(/_/g, ' '));
      e.kind = (e.text.indexOf(' ') >= 0 && /^[a-z]/.test(e.text)) ? 'phrase' : 'stem';
    }
    parseTags(toks, 2, e);
    if (e.flags.j) e.kind = 'noun';
    return e;
  }
  function parseGen(toks?: any, script?: any): any {
    const raw = toks[0]; let e: any;
    if (script) {
      const m = /^([^/]+)\/([^/]+)\/(.+)$/.exec(raw);
      e = newEntry(m ? m[1] : null); if (m) { e.k = m[1]; e.r = m[2]; e.rd = m[3]; } e.form = 'ja';
    } else if (raw.slice(0, 1) === '-') { e = newEntry(raw.slice(1)); e.form = 'suf'; }
    else if (raw.slice(0, 1) === '_') { e = newEntry(raw.slice(1).replace(/_/g, ' ')); e.form = 'after'; }
    else if (raw.slice(-1) === '_') { e = newEntry(raw.slice(0, -1).replace(/_/g, ' ')); e.form = 'before'; }
    else if (raw.slice(-1) === '^') { e = newEntry(raw.slice(0, -1)); e.form = 'pre'; }
    else if (raw.slice(-1) === '-') { e = newEntry(raw); e.form = 'hyph'; }
    else { e = newEntry(raw); e.form = 'after'; }
    e.raw = raw;
    parseTags(toks, 2, e);
    return e;
  }
  function parseAffix(toks?: any, script?: any): any {
    const raw = toks[0]; let e: any;
    if (script) {
      const m = /^([^/]+)\/(.+)$/.exec(raw);
      e = newEntry(m ? m[1] : null); if (m) { e.k = m[1]; e.r = m[2]; }
    } else e = newEntry(raw.replace(/_/g, ' '));
    e.raw = raw;
    const tx = e.text || '';
    e.needR = tx.indexOf('%r') >= 0 || (e.r || '').indexOf('%r') >= 0;
    e.needK = tx.indexOf('%k') >= 0;
    e.needP = tx.indexOf('%p') >= 0;
    e.needT = tx.indexOf('%t') >= 0 || (e.r || '').indexOf('%t') >= 0;
    e.needM = tx.indexOf('%m') >= 0 || tx.indexOf('%M') >= 0;
    e.needB = tx.indexOf('%b') >= 0 || tx.indexOf('%B') >= 0;
    e.needD = tx.indexOf('%D') >= 0;
    e.needE = tx.indexOf('%E') >= 0;
    e.hasS = tx.indexOf('%s') >= 0 || tx.indexOf('%l') >= 0;
    parseTags(toks, 2, e);
    // (a bare one-word whole name takes the town's name in front: "Ashford Narrows"; never an evocative or industry
    // name, NEXT_PHASE_BRIEF 61)
    if (!script && !e.hasS && tx.indexOf('%') < 0 && !/[ \-]/.test(tx) && !e.flags.g && !e.flags.i) { e.bare = tx; e.text = '%s ' + tx; e.hasS = true; }
    return e;
  }
  M.parseSpec = parseSpec; M.parseGen = parseGen; M.parseAffix = parseAffix;

  // D: a raw language table (data.js lang[x], text strings). edits: { spec, gen, affix } replacement texts.
  function toBytes(v?: any): any {
    if (typeof v === 'string') return b(v);
    if (Array.isArray(v)) return v.map(toBytes);
    if (v && typeof v === 'object') { const o: any = {}; for (const k in v) o[k] = toBytes(v[k]); return o; }
    return v;
  }
  const CACHE: any = {};
  M.lang = function (id?: any): any {
    const base = id === 'ja_r' ? 'ja' : id;
    if (CACHE[id]) return CACHE[id];
    const raw = DATA.lang[base || ''];
    if (!raw || raw.spec == null) return null;
    const ed = (opt.edits || {})[base] || {};
    const D = toBytes(Object.assign({}, raw, ed));
    const L: any = { id: b(id), data: D, script: D.script ? (id === 'ja' ? 'kanji' : 'romaji') : null, specs: [], gens: [], affixes: [],
      maxCons: D.maxCons || 3, dbl: D.dbl || '', dropE: D.dropE, vv: D.vv, pOnly: D.pOnly, noPhrasePre: D.noPhrasePre };
    for (const toks of lines(D.spec)) L.specs.push(parseSpec(toks, D.script));
    for (const toks of lines(D.gen)) L.gens.push(parseGen(toks, D.script));
    for (const toks of lines(D.affix)) L.affixes.push(parseAffix(toks, D.script));
    // (NEXT_PHASE_BRIEF 61: the s61 lines, each +61)
    for (const toks of lines(D.affix61)) { const a = parseAffix(toks, D.script); a.flags['61'] = true; L.affixes.push(a); }
    L.saints = split(D.saints, '|');
    L.quota = {};
    String(D.shapes || '').replace(/([A-Za-z_]+):([0-9.]+)/g, (m0?: any, k?: any, v?: any) => { L.quota[k] = Number(v); return m0; });
    L.common = split(D.common, '|');
    L.areas = D.areas || null;
    L.shared = {};
    for (const g of split(D.shared, '|')) L.shared[g] = true;
    L.articles = D.articles || null;
    // (NEXT_PHASE_BRIEF 53 Part B: the layers' raw gens / affixes, "+p" the personal stems; the character kinds' forms)
    L.layerSet = {}; L.layerAny = {}; L.layerP = {};
    for (const lay of M.LAYERS) {
      const set: any = {};
      for (const tok of String((D.layers && typeof D.layers === 'object' && D.layers[lay]) || '').split(/[ \t\r\n]+/)) {
        if (tok === '') continue;
        if (tok === '+p') L.layerP[lay] = true; else { set[tok] = true; L.layerAny[tok] = true; }
      }
      L.layerSet[lay] = set;
    }
    L.charForms = {};
    if (D.charForms && typeof D.charForms === 'object') {
      for (const kind in D.charForms) {
        const set: any = {};
        for (const tok of String(D.charForms[kind]).split(/[ \t\r\n]+/)) if (tok !== '') set[tok] = true;
        L.charForms[kind] = set;
      }
    }
    // (NEXT_PHASE_BRIEF 61: the s61 kinds' forms, per kind replacing the base set)
    L.charForms61 = Object.assign({}, L.charForms);
    if (D.charForms61 && typeof D.charForms61 === 'object') {
      for (const kind in D.charForms61) {
        const set: any = {};
        for (const tok of String(D.charForms61[kind]).split(/[ \t\r\n]+/)) if (tok !== '') set[tok] = true;
        L.charForms61[kind] = set;
      }
    }
    for (const a of L.affixes) M.affixShape(a);
    L.groups = [];
    {
      const seen: any = {};
      const addG = (g: any) => { if (g != null && !seen[g]) { seen[g] = true; L.groups.push(g); } };
      if (D.areas && typeof D.areas === 'object') { addG(D.areas.core); addG(D.areas.coast); for (const g of (Array.isArray(D.areas.edge) ? D.areas.edge : [])) addG(g); }
      for (const e of L.specs) addG(e.grp);
      for (const e of L.gens) addG(e.grp);
    }
    L.compatSet = {};
    for (const pr of (Array.isArray(D.compat) ? D.compat : [])) {
      const m = /^([^:]+):([^:]+)$/.exec(pr);
      if (m) { L.compatSet[m[1] + ':' + m[2]] = true; L.compatSet[m[2] + ':' + m[1]] = true; }
    }
    L.dirWords = {};
    const dw = split(D.dirs, '|');
    ['north', 'south', 'east', 'west'].forEach((t?: any, i?: any) => { if (dw[i]) L.dirWords[t] = dw[i]; });
    L.worksGens = [];
    for (const g of split(D.worksGens, '|')) L.worksGens.push(parseGen([g, 'works:.5', 'any:.5'], D.script));
    // (NEXT_PHASE_BRIEF 60: does the language have flavor parts, +n)
    L.hasFlavor = L.specs.some((e: any) => e.flags.n) || L.gens.some((e: any) => e.flags.n);
    CACHE[id] = L;
    return L;
  };

  // the climate's shape table (NEXT_PHASE_BRIEF 53 Part B, ot_placename.climateOf)
  M.LAYERS = PN.LAYERS || ['old', 'mid', 'late'];
  M.climateOf = function (L?: any, climate?: any): any {
    if (!L) return null;
    L.clim = L.clim || {};
    const key = climate || 'temperate';
    if (L.clim[key]) return L.clim[key];
    const Cs = (L.data.climate && typeof L.data.climate === 'object') ? L.data.climate[b(key)] : null;
    const out: any = { quota: L.quota, words: L.data.words != null ? Number(L.data.words) : null, boost: {}, veto: {}, shared: {},
      saints: L.saints, areas: L.areas, three: false, group: null };
    if (Cs && typeof Cs === 'object') {
      if (Cs.shapes) { out.quota = {}; String(Cs.shapes).replace(/([A-Za-z_]+):([0-9.]+)/g, (m0?: any, k?: any, v?: any) => { out.quota[k] = Number(v); return m0; }); }
      if (Cs.words != null && !isNaN(Number(Cs.words))) out.words = Number(Cs.words);
      for (const tok of String(Cs.boost || '').split(/[ \t\r\n]+/)) if (tok !== '') out.boost[tok] = true;
      for (const tok of String(Cs.veto || '').split(/[ \t\r\n]+/)) if (tok !== '') out.veto[tok] = true;
      for (const g of split(Cs.shared, '|')) out.shared[g] = true;
      if (Cs.saints) out.saints = split(Cs.saints, '|');
      if (Cs.areas && typeof Cs.areas === 'object') out.areas = Cs.areas;
      out.three = Cs.three === true;
      const gm = /^([A-Za-z_]+):([0-9.]+)$/.exec(String(Cs.group || ''));
      if (gm) out.group = { grp: gm[1], share: Number(gm[2]) };
    }
    L.clim[key] = out;
    return out;
  };
  M.layerAdj = function (L?: any, e?: any, lay?: any): any {
    if (!L || lay == null || !L.layerSet) return 0;
    let own = false, any = false;
    if (e.raw) { own = !!(L.layerSet[lay] && L.layerSet[lay][e.raw]); any = L.layerAny[e.raw] === true; }
    else if (e.flags && e.flags.p) { own = L.layerP[lay] === true; any = !!(L.layerP.old || L.layerP.mid || L.layerP.late); }
    if (own) return C.LAYER_ON;
    if (any) return -C.LAYER_OFF;
    return 0;
  };

  // fit
  M.expandSite = function (w?: any): any {
    const x: any = {};
    for (const t of M.TAGS) {
      const v = w[t];
      if (v != null) {  // (Lua: any number is true, 0 too)
        if ((x[t] || 0) < v) x[t] = v;
        const up = function (tag?: any, f?: any, depth?: any): any {
          for (const par of (M.PARENT[tag] || [])) {
            if ((x[par] || 0) < v * f) x[par] = v * f;
            if (depth < 3) up(par, f * 0.7, depth + 1);
          }
        };
        up(t, 0.7, 1);
      }
    }
    x.any = Math.max(x.any || 0, C.ANY);
    return x;
  };
  M.ranked = function (w?: any): any {
    const out: any = [];
    for (const t of M.TAGS) if ((w[t] || 0) >= 0.2) out.push([t, w[t] * (M.SPEC[t] || 1)]);
    out.sort((a?: any, c?: any) => a[1] !== c[1] ? c[1] - a[1] : M.TAG_INDEX[a[0]] - M.TAG_INDEX[c[0]]);
    return out;
  };
  // ---------------------------------------------------------------- the climate (ot_climate.lua, NEXT_PHASE_BRIEF 49)
  const CLD = DATA.climate || { VETO_TAGS: {}, SITE: {}, WORDS: {}, LANG_OF: {}, EXTRA: 9, VETO_MIN: 0.3, MAX_WORDS: 12 };
  M.CL = CLD;
  const CL_LOW: any = { '\xc3\x84': '\xc3\xa4', '\xc3\x96': '\xc3\xb6', '\xc3\x9c': '\xc3\xbc', '\xc3\x85': '\xc3\xa5',
    '\xc3\x98': '\xc3\xb8', '\xc3\x86': '\xc3\xa6', '\xc3\x89': '\xc3\xa9', '\xc3\x88': '\xc3\xa8', '\xc3\x8a': '\xc3\xaa',
    '\xc3\x81': '\xc3\xa1', '\xc3\x8d': '\xc3\xad', '\xc3\x93': '\xc3\xb3', '\xc3\x9a': '\xc3\xba', '\xc3\x87': '\xc3\xa7' };
  const clWords: any = {};
  function clList(climate?: any, lang?: any): any {
    const key = climate + '|' + lang;
    if (clWords[key]) return clWords[key];
    const t = CLD.WORDS[climate], list: any = [];
    if (t) {
      for (const w of String(t[lang] || '').split(/\s+/)) if (w) list.push(b(w));
      if (lang !== 'en' && lang !== 'ja') for (const w of String(t.en || '').split(/\s+/)) if (w) list.push(b(w));
    }
    clWords[key] = list;
    return list;
  }
  M.vetoTag = (climate?: any, t?: any) => !!(CLD.VETO_TAGS[climate] && CLD.VETO_TAGS[climate][t]);
  M.wordMisfit = function (name?: any, climate?: any, cls?: any): any {
    if (name == null || name === '' || climate == null) return null;
    const lang = CLD.LANG_OF[cls] || 'en';
    const list = clList(climate, lang);
    if (!list.length) return null;
    if (lang === 'ja') { for (const w of list) if (name.indexOf(w) >= 0) return w; return null; }
    const low = name.replace(/[A-Z]/g, (c: any) => c.toLowerCase()).replace(/\xc3[\x80-\x9f]/g, (ch: any) => CL_LOW[ch] || ch);
    const words = low.split(/[\s\-'.,\/]+/).filter((x: any) => x);
    for (let n = 0; n < Math.min(words.length, CLD.MAX_WORDS); n++) {
      const word = words[n];
      if (CLD.NOT_WORDS && CLD.NOT_WORDS[word]) continue;
      for (const w of list) if (word === w || (word.length > w.length && word.length <= w.length + CLD.EXTRA && word.slice(0, w.length) === w)) return w;
    }
    return null;
  };
  M.misfit = function (ctx?: any, word?: any, reason?: any): any {
    if (!ctx) return;
    ctx.misfit = ctx.misfit || {};
    const k = String(word == null ? '?' : word).replace(/[\s,:=]/g, '_') + ':' + reason;
    ctx.misfit[k] = (ctx.misfit[k] || 0) + 1;
  };
  M.climateVeto = function (ctx?: any, e?: any): any {
    const c = ctx && ctx.climate;
    if (c == null) return false;
    if (ctx.cl && e.raw && ctx.cl.veto[e.raw]) { M.misfit(ctx, e.k || e.text, c + '/form'); return true; }
    for (const p of (e.tl || [])) if (p[1] >= CLD.VETO_MIN && M.vetoTag(c, p[0])) { M.misfit(ctx, e.k || e.text, c + '/' + p[0]); return true; }
    return false;
  };
  M.climateWord = function (ctx?: any, name?: any): any {
    if (!ctx || ctx.climate == null) return false;
    const bad = M.wordMisfit(name, ctx.climate, M.CLS_OF_GEN[ctx.lang] || ctx.lang);
    if (bad) { M.misfit(ctx, bad, ctx.climate); return true; }
    return false;
  };

  M.fit = function (e?: any, x?: any): any {
    let best = 0, second = 0, bt: any = null;
    for (const p of e.x) {
      const s = x[p[0]];
      if (s !== undefined) {
        const v = s * p[1] * (M.SPEC[p[0]] || 1);
        if (v > best) { second = best; best = v; bt = p[0]; } else if (v > second) second = v;
      }
    }
    let pen = 0;
    for (const p of e.tl) {
      const t = p[0];
      if (x[t] === undefined) {
        const c = M.CONTRA[t] || 0;
        if (c > 0) {
          let par = false;
          for (const q of (M.PARENT[t] || [])) if (x[q] !== undefined) par = true;
          pen = pen + p[1] * c * (par ? 0.3 : 1);
        }
      }
    }
    return [best + 0.3 * second - pen, bt];
  };

  // joining
  const VOWEL = /[aeiouy\x80-\xff]/;
  function isV(ch?: any): any { return ch !== '' && VOWEL.test(ch); }
  function sufJoin(L?: any, a?: any, bb?: any): any {
    let la = lowerAll(a);
    const first = bb.slice(0, 1);
    if (L.dropE && la.slice(-1) === 'e' && isV(first) && blen(la) > 2) { a = a.slice(0, -1); la = la.slice(0, -1); }
    const x = la.slice(-1);
    if (x === first && /^[a-z]$/.test(x)) {
      if (L.dbl.indexOf(x) < 0) return null;
      if (la.slice(-2, -1) === x || bb.slice(1, 2) === x) return null;
    }
    if (isV(x) && isV(first) && !L.vv) return null;
    const tc = (/[^aeiouy\x80-\xff]*$/.exec(la) || [''])[0].length;
    const lc = (/^[^aeiouy\x80-\xff]*/.exec(bb) || [''])[0].length;
    if (tc + lc > L.maxCons) return null;
    return a + bb;
  }
  M.sufJoin = sufJoin;
  function elide(g?: any, s?: any): any {
    if (/[aeiou]/.test(g.slice(-1)) && /[aeiouAEIOU]/.test(s.slice(0, 1))) return g.slice(0, -1) + s;
    return g + s;
  }
  function adjForm(e?: any, gender?: any): any {
    if (e.kind !== 'adj') return e.text;
    const i = ({ m: 1, f: 2, mp: 3, fp: 4 } as Record<string, number>)[gender || 'm'] || 1;
    if (e.forms[i - 1]) return e.forms[i - 1];
    if (i >= 3) { const w = e.forms[i - 3] || e.forms[0]; return w + (/[aeiouy]/.test(w.slice(-1)) ? 's' : 'es'); }
    return e.forms[0];
  }
  M.sameWord = function (a?: any, c?: any): any {
    if (typeof a !== 'string' || typeof c !== 'string') return false;
    const wa: any = {};
    for (const tok of (lowerAll(a).match(/[^ \-']+/g) || [])) if (tok.length >= 3) wa[tok.slice(0, 4)] = true;
    for (const tok of (lowerAll(c).match(/[^ \-']+/g) || [])) if (tok.length >= 3 && wa[tok.slice(0, 4)]) return true;
    return false;
  };
  M.compatible = function (L?: any, a?: any, c?: any): any {
    if (a == null || c == null || a === c) return true;
    return L != null && L.compatSet != null && L.compatSet[a + ':' + c] === true;
  };
  M.join = function (L?: any, s?: any, g?: any, strict?: any): any {
    if (s.cls && g.cls && s.cls === g.cls) return null;
    if (L.script) {
      if (g.form !== 'ja' || s.k == null) return null;
      if (s.k === g.k) return null;
      if (L.script === 'kanji') return s.k + g.k;
      const r2 = s.flags.r ? g.rd : g.r;
      let r1 = s.r;
      if (r1.slice(-1) === 'n' && /^[aeiouy]/.test(r2.slice(0, 1))) r1 = r1 + "'";
      return M.capFirst(r1 + r2);
    }
    if (M.sameWord(s.text, g.text)) return null;
    if (g.flags.w && (s.flags.f || s.flags.p)) return null;
    if (!M.compatible(L, s.grp, g.grp)) return null;
    // (+x: parts that only meet their own group; the generic's gender agrees, NEXT_PHASE_BRIEF 53 Part B)
    if ((g.flags.x || s.flags.x) && s.grp !== g.grp) return null;
    if (g.flags.x && g.gender) {
      if (s.kind === 'adj') { if (g.gender !== 'm' && g.gender !== 'f') return null; }
      else if (s.gender !== g.gender) return null;
    }
    if (strict && s.grp && g.grp && s.grp !== g.grp && !(L.shared[s.grp] || L.shared[g.grp])) return null;
    const need = g.flags;
    if (need.p && !s.flags.p) return null;
    if (need.c && !(s.flags.c || s.river)) return null;
    if (s.flags.c && !need.c) return null;
    if (L.pOnly && s.flags.p && !need.p) return null;
    if (need.t && !s.flags.t) return null;
    const form = g.form;
    if (form === 'suf') {
      if (s.kind !== 'stem') return null;
      const ls = lowerAll(s.text), lg = g.text;
      if (ls.length >= 3 && (lg.indexOf(ls) >= 0 || ls.indexOf(lg) >= 0)) return null;
      if (lg.length >= 3 && ls.slice(-lg.length) === lg) return null;
      return sufJoin(L, s.text, g.text);
    } else if (form === 'after') {
      if (s.kind !== 'stem') return null;
      if (lowerAll(s.text) === lowerAll(g.text)) return null;
      return s.text + ' ' + g.text;
    } else if (form === 'before') {
      if (s.river && L.id !== 'usa') return null;
      if (s.kind === 'stem' || s.kind === 'phrase') {
        if (s.kind === 'stem' && /^[a-z]/.test(s.text)) return null;
        return g.text + ' ' + s.text;
      } else if (s.kind === 'adj') return g.text + ' ' + M.capFirst(adjForm(s, g.gender));
      return null;
    } else if (form === 'pre') {
      if (s.kind === 'phrase') { if (L.noPhrasePre) return null; return g.text + ' ' + s.text; }
      if (s.kind === 'adj') return elide(g.text, adjForm(s, g.gender));
      if (s.kind === 'noun') return elide(g.text, s.text);
      if (s.flags.c || s.river) return g.text + M.lowerFirst(s.text);
      return null;
    } else if (form === 'hyph') {
      if (s.kind === 'stem' && (s.river || s.flags.c)) return g.text + s.text;
      if (s.kind === 'phrase') return g.text + s.text.replace(/ /g, '-');
      return null;
    }
    return null;
  };

  // blocklist
  const BLOCK_SUB = DATA.block.sub.map(b), BLOCK_CJK = DATA.block.cjk.map(b), BLOCK_WORD: any = {};
  for (const w of DATA.block.word) BLOCK_WORD[b(w)] = true;
  M.blocked = function (name?: any): any {
    if (typeof name !== 'string') return true;
    for (const c of BLOCK_CJK) if (name.indexOf(c) >= 0) return true;
    const l = lowerAll(name);
    for (const s of BLOCK_SUB) if (l.indexOf(s) >= 0) return true;
    for (const tok of (l.match(/[^ \t\-'.]+/g) || [])) if (BLOCK_WORD[tok]) return true;
    return false;
  };
  M.wellFormed = function (L?: any, base?: any): any {
    if (typeof base !== 'string' || base === '') return false;
    if (L.script === 'kanji') return M.chars(base) <= C.MAX_KANJI;
    if (M.chars(base) > C.MAX_BASE) return false;
    if (/([a-z])\1\1/.test(lowerAll(base))) return false;
    return true;
  };

  // context
  M.newCtx = function (lang?: any, seed?: any, real?: any, used?: any): any {
    const L = M.lang(lang);
    if (!L) return null;
    const ctx: any = { L, lang, seed: Number(seed) || 1, real: real || {}, used: {}, usedLower: {}, specUse: {}, genUse: {},
      affUse: {}, anchors: [], riverNames: {}, lakeNames: {}, budget: null, featUse: {}, featWords: {}, riverFrame: {}, shapeUse: {},
      rules: M.RULES, opaqueN: 0, flavorN: 0 };
    for (const n in (used || {})) M.take(ctx, n);
    return ctx;
  };
  M.take = function (ctx?: any, name?: any): any { ctx.used[name] = true; ctx.usedLower[lowerAll(name)] = true; };
  M.free = function (ctx?: any, name?: any): any {
    if (typeof name !== 'string') return false;
    const l = lowerAll(name);
    return !ctx.used[name] && !ctx.usedLower[l] && !ctx.real[l] && !M.blocked(name);
  };
  function clamp(v?: any, a?: any, c?: any): any { return v < a ? a : (v > c ? c : v); }
  // the plan's seeded draws (ot_placename.draw: the seed and the item through the hash once more)
  function draw(seed?: any, item?: any, salt?: any): any { return unit(hash(hash(seed, 'plan53'), item == null ? 0 : item), salt); }
  M.draw = draw;
  // the map's dialect areas (ot_placename.regions, NEXT_PHASE_BRIEF 53 item 3)
  M.regions = function (ctx?: any, towns?: any, ws?: any): any {
    ctx.anchors = [];
    ctx.areas = null;
    const L = ctx.L, cl = ctx.cl, A = (cl && cl.areas) || L.areas;
    if (!A || typeof A !== 'object' || A.core == null) return;
    const pts: any = [];
    towns.forEach((t?: any, i?: any) => {
      if (typeof t.x === 'number' && typeof t.y === 'number') pts.push({ x: t.x, y: t.y, w: (ws && ws[i]) || t.w || {}, alt: typeof t.alt === 'number' ? t.alt : null });
    });
    if (pts.length < 2) return;
    const line = (sel: any) => {
      let n = 0, cx = 0, cy = 0;
      for (const p of sel) { n++; cx += p.x; cy += p.y; }
      if (n < 2) return null;
      cx /= n; cy /= n;
      let sxx = 0, syy = 0, sxy = 0;
      for (const p of sel) { const dx = p.x - cx, dy = p.y - cy; sxx += dx * dx; syy += dy * dy; sxy += dx * dy; }
      if (sxx + syy < 1) return null;
      const ang = 0.5 * Math.atan2(2 * sxy, sxx - syy);
      return [{ x: cx, y: cy }, { x: Math.cos(ang), y: Math.sin(ang) }];
    };
    const pick = (f: any) => pts.filter((p: any) => f(p.w));
    let cd = line(pick((w: any) => (w.mainvalley || 0) > 0));
    if (!cd) cd = line(pick((w: any) => (w.range || 0) > 0 || (w.summit || 0) > 0 || (w.divide || 0) > 0));
    let c: any, d: any;
    if (cd) { c = cd[0]; d = cd[1]; }
    else {
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity, cx = 0, cy = 0;
      for (const p of pts) { x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y); x1 = Math.max(x1, p.x); y1 = Math.max(y1, p.y); cx += p.x; cy += p.y; }
      c = { x: cx / pts.length, y: cy / pts.length };
      d = (x1 - x0 >= y1 - y0) ? { x: 0, y: 1 } : { x: 1, y: 0 };
    }
    const nrm: any = { x: -d.y, y: d.x };
    {
      const ss: any = []; let pos = 0;
      for (const p of pts) { const v = (p.x - c.x) * nrm.x + (p.y - c.y) * nrm.y; ss.push(v); if (v >= 0) pos++; }
      const minSide = Math.max(1, floor(pts.length * 0.2));
      if (pos < minSide || pts.length - pos < minSide) {
        ss.sort((a?: any, b2?: any) => a - b2);
        let m = ss[floor((ss.length + 1) / 2) - 1];
        if (ss.length % 2 === 0) m = (ss[ss.length / 2 - 1] + ss[ss.length / 2]) / 2;
        c = { x: c.x + nrm.x * m, y: c.y + nrm.y * m };
      }
    }
    const sideOf = (x?: any, y?: any) => (x - c.x) * nrm.x + (y - c.y) * nrm.y;
    const coastScore = (p: any) => { const w = p.w; return Math.max(w.coast || 0, w.bay || 0, w.headland || 0, w.island || 0, w.spit || 0, w.mouth || 0) + 0.7 * (w.east || 0); };
    const highScore = (p: any) => {
      const w = p.w, alt = p.alt != null ? clamp(p.alt / 400, 0, 1) : 0;
      return Math.max(w.hill || 0, w.mountain || 0, w.moor || 0, w.summit || 0, w.range || 0, w.peak || 0, w.hilltop || 0) + 0.7 * (w.west || 0) + alt;
    };
    const sum: any = { '1': { n: 0, c: 0, h: 0 }, '-1': { n: 0, c: 0, h: 0 } };
    for (const p of pts) {
      p.s = sideOf(p.x, p.y);
      const k = p.s >= 0 ? '1' : '-1';
      sum[k].n++; sum[k].c += coastScore(p); sum[k].h += highScore(p);
    }
    const mean = (k?: any, f?: any) => sum[k].n > 0 ? sum[k][f] / sum[k].n : 0;
    const dC = mean('1', 'c') - mean('-1', 'c'), dH = mean('1', 'h') - mean('-1', 'h');
    const seedSide = draw(ctx.seed, 1, 'areaside') < 0.5 ? 1 : -1;
    const edges = Array.isArray(A.edge) ? A.edge : [];
    let three = pts.length >= C.AREAS3_MIN && edges.length > 0 && ((cl && cl.three) || draw(ctx.seed, 2, 'areas3') < C.AREAS3_P);
    const edgeName = edges.length > 0 ? edges[lmod(floor(draw(ctx.seed, 3, 'areaedge') * edges.length), edges.length)] : null;
    const R: any = { c, n: nrm, three };
    let roleA: any, roleB: any;
    if (three || Math.abs(dC) >= Math.abs(dH) || edgeName == null) {
      const cs = dC > 0 ? 1 : (dC < 0 ? -1 : seedSide);
      R.coastSide = cs;
      roleA = cs === 1 ? 'coast' : 'core'; roleB = cs === 1 ? 'core' : 'coast';
    } else {
      const es = dH > 0 ? 1 : (dH < 0 ? -1 : seedSide);
      R.coastSide = 0; R.edgeSide = es;
      roleA = es === 1 ? 'edge' : 'core'; roleB = es === 1 ? 'core' : 'edge';
    }
    R.roleOf = { '1': roleA, '-1': roleB };
    if (three) {
      const coreK = R.coastSide === 1 ? -1 : 1;
      const far: any = [];
      for (const p of pts) if ((p.s >= 0 ? 1 : -1) === coreK) far.push(Math.abs(p.s));
      far.sort((a?: any, b2?: any) => b2 - a);
      const k = Math.min(Math.max(1, floor(C.FRINGE * pts.length + 0.5)), far.length - 1);
      if (k >= 1) { R.fringe = far[k - 1]; R.coreK = coreK; } else R.three = false;
    }
    const own: any = { core: A.core, coast: A.coast, edge: edgeName || A.core };
    for (const role in own) {
      const g = own[role], w: any = {};
      for (const gg of L.groups) {
        if (gg === g) w[gg] = C.DIALECT_OWN;
        else if ((L.shared[gg] || (cl && cl.shared[gg])) && M.compatible(L, g, gg)) w[gg] = C.DIALECT_SHARED;
        else w[gg] = C.DIALECT_FOREIGN;
      }
      R[role] = { name: g, role, w };
    }
    ctx.areas = R;
  };
  // (lab) the area object of dialect group g, as regions builds it: { name, w }
  M.areaObj = function (L?: any, g?: any): any {
    if (!L || L.groups.indexOf(g) < 0) return null;
    const w: any = {};
    for (const gg of L.groups) w[gg] = gg === g ? C.DIALECT_OWN : ((L.shared[gg] && M.compatible(L, g, gg)) ? C.DIALECT_SHARED : C.DIALECT_FOREIGN);
    return { name: g, role: 'lab', w, hybrid: false };
  };
  M.dialectAt = function (ctx?: any, x?: any, y?: any): any {
    const R = ctx.areas;
    if (!R || typeof x !== 'number' || typeof y !== 'number') return null;
    const s = (x - R.c.x) * R.n.x + (y - R.c.y) * R.n.y;
    const k = s >= 0 ? 1 : -1;
    let role = R.roleOf[String(k)], dist = Math.abs(s), otherRole = R.roleOf[String(-k)];
    if (R.three && k === R.coreK) {
      if (Math.abs(s) >= R.fringe) { role = 'edge'; otherRole = 'core'; dist = Math.abs(s) - R.fringe; }
      else if (R.fringe - Math.abs(s) < dist) { otherRole = 'edge'; dist = R.fringe - Math.abs(s); }
    }
    const a = R[role];
    return { name: a.name, role, w: a.w, hybrid: dist <= C.BORDER_M, other: R[otherRole] };
  };
  function angDiffAxis(a?: any, c?: any): any { let d = Math.abs(a - c) % Math.PI; if (d > Math.PI / 2) d = Math.PI - d; return d; }
  M.riverSystems = function (towns?: any, linkM?: any): any {
    linkM = linkM == null ? C.RIVER_LINK_M : linkM;
    const list: any = [];
    for (const t of towns) if (t.river && typeof t.x === 'number' && list.length < C.MAX_RIVER_TOWNS) list.push(t);
    list.sort((a?: any, c?: any) => (Number(a.id) || 0) - (Number(c.id) || 0));
    const parent = list.map((_?: any, i?: any) => i);
    const find = (i: any) => { while (parent[i] !== i) i = parent[i]; return i; };
    const lim = C.RIVER_DEG * Math.PI / 180;
    for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) {
      const a = list[i], c = list[j];
      const d = Math.sqrt(Math.pow(a.x - c.x, 2) + Math.pow(a.y - c.y, 2));
      if (d <= linkM) {
        const bearing = Math.atan2(c.y - a.y, c.x - a.x);
        let okA = a.axis == null || angDiffAxis(a.axis, bearing) <= lim;
        const okB = c.axis == null || angDiffAxis(c.axis, bearing) <= lim;
        if (a.axis == null && c.axis == null) okA = d <= linkM / 2;
        if (okA && okB) { const ri = find(i), rj = find(j); if (ri !== rj) parent[Math.max(ri, rj)] = Math.min(ri, rj); }
      }
    }
    const sysOf: any = {}, systems: any = [], idx: any = {};
    list.forEach((t?: any, i?: any) => {
      const r = find(i);
      if (idx[r] === undefined) { systems.push({ ids: [], x: 0, y: 0 }); idx[r] = systems.length; }
      const s = systems[idx[r] - 1];
      s.ids.push(t.id); s.x += t.x; s.y += t.y; sysOf[t.id] = idx[r];
    });
    for (const s of systems) { s.x /= s.ids.length; s.y /= s.ids.length; }
    return [sysOf, systems];
  };
  M.lakeSystems = function (towns?: any): any {
    const list: any = [];
    for (const t of towns) if (t.lake && typeof t.x === 'number') list.push({ id: t.id, x: t.x, y: t.y, river: true });
    return M.riverSystems(list, C.LAKE_LINK_M * 2);
  };
  function gen2(syl?: any, seed?: any, i?: any): any {
    const s1 = split(syl[0], '|'), s2 = split(syl[1], '|');
    if (s1.length === 0 || s2.length === 0) return null;
    return s1[hash(seed, 'rs1', i) % s1.length] + s2[hash(seed, 'rs2', i) % s2.length];
  }
  M.riverName = function (ctx?: any, k?: any): any {
    const L = ctx.L, D = L.data;
    if (L.script) {
      const cands: any = [];
      for (const e of L.specs) for (const p of e.tl) {
        if (p[0] === 'spring' || p[0] === 'river' || p[0] === 'brook' || (p[0] === 'any' && p[1] <= 0.3)) { cands.push(e); break; }
      }
      const m: any = /^([^/]+)\/([^/]+)\/(.+)$/.exec(D.riverGens || b('川/kawa/gawa'));
      const gk = m[1], gr = m[2], grd = m[3];
      const start = hash(ctx.seed, 'river', k);
      for (let i = 0; i < cands.length; i++) {
        const e = cands[(start + i) % cands.length];
        const n = L.script === 'kanji' ? (e.k + gk) : M.capFirst(e.r + (e.flags.r ? grd : gr));
        if (M.free(ctx, n) && !ctx.riverNames[n]) { ctx.riverNames[n] = true; return { n, s: L.script === 'kanji' ? e.k : e.r, e }; }
      }
      return null;
    }
    const list = split(D.rivers, '|'), suffixes = split(D.riverSuffix, '|');
    const start = list.length > 0 ? hash(ctx.seed, 'river', k) % list.length : 0;
    const tryS = (stem?: any, i?: any) => {
      if (stem == null || ctx.riverNames[stem]) return null;
      let full = stem;
      if (suffixes.length > 0) full = stem + suffixes[hash(ctx.seed, 'rsuf', k, i) % suffixes.length];
      if (M.free(ctx, full) && M.free(ctx, stem) && !M.blocked(full) && !M.climateWord(ctx, full)) { ctx.riverNames[stem] = true; return { n: full, s: stem }; }
      return null;
    };
    for (let i = 0; i < list.length; i++) { const r = tryS(list[(start + i) % list.length], i); if (r) return r; }
    if (D.riverSyl) for (let i = 1; i <= 60; i++) { const r = tryS(gen2(D.riverSyl, ctx.seed + k, i), i); if (r) return r; }
    return null;
  };
  M.lakeName = function (ctx?: any, k?: any, high?: any, grp?: any): any {
    const D = ctx.L.data;
    const stems = split(D.lakes, '|');
    if (stems.length === 0) return null;
    const by = D.lakeGensBy && typeof D.lakeGensBy === 'object' && grp ? D.lakeGensBy[grp] : null;
    let gens = split(by || D.lakeGens, '|').filter((g: any) => high || g.indexOf('tarn') < 0);
    if (gens.length === 0 && by) gens = split(D.lakeGens, '|').filter((g: any) => high || g.indexOf('tarn') < 0);
    const start = hash(ctx.seed, 'lake', k) % stems.length;
    for (let i = 0; i < stems.length; i++) {
      const stem = stems[(start + i) % stems.length];
      let full: any = null;
      if (D.lakeForm) full = D.lakeForm.replace('%s', stem);
      else if (gens.length > 0) { const g = gens[hash(ctx.seed, 'lgen', k, i) % gens.length]; full = sufJoin(ctx.L, stem, g) || (stem + g); }
      if (full && !ctx.lakeNames[full] && M.free(ctx, full) && !M.climateWord(ctx, full)) { ctx.lakeNames[full] = true; return { n: full, s: stem }; }
    }
    return null;
  };

  // naming one town
  M.repeats = function (a?: any, base?: any): any {
    const words = a.text.replace(/%[A-Za-z]/g, ' ');
    const lb = lowerAll(base);
    for (let tok of (lowerAll(words).match(/[^ \-']+/g) || [])) {
      if (tok.length >= 5 && tok.slice(-1) === 's') tok = tok.slice(0, -1);
      if (tok.length >= 3 && lb.indexOf(tok) >= 0) return true;
      if (tok.length >= 4 && lb.indexOf(tok.slice(0, 4)) >= 0) return true;
    }
    if (/ [a-z]/.test(base) && / [a-z]/.test(words)) return true;
    return false;
  };
  function fillAffix(L?: any, a?: any, base?: any, t?: any): any {
    const tpl = L.script === 'romaji' ? a.r : a.text;
    if (tpl == null) return null;
    if (a.needR && !(t.river && t.river.n)) return null;
    if (a.needT && !(t.river && t.river.s)) return null;
    if (a.needK && !(t.lake && t.lake.n)) return null;
    if (a.needM && !(t.mount && t.mount.s)) return null;
    if (a.needB && !(t.bay && t.bay.s)) return null;
    if (a.needD && !(t.dir && L.dirWords[t.dir])) return null;
    if (a.needE && !(t.ldir && L.dirWords[t.ldir])) return null;
    let saint: any = null;
    if (a.needP) {
      const saints = t.saints || L.saints;
      if (saints.length === 0) return null;
      saint = saints[hash(t.seed || 1, 'saint', t.id || 0) % saints.length];
    }
    return tpl.replace(/%([A-Za-z])/g, (m?: any, c?: any) => {
      if (c === 's') return base; if (c === 'l') return M.lowerFirst(base);
      if (c === 'r') return t.river.n; if (c === 't') return t.river.s; if (c === 'k') return t.lake.n;
      if (c === 'm') return t.mount.s; if (c === 'M') return t.mount.n; if (c === 'b') return t.bay.s; if (c === 'B') return t.bay.n;
      if (c === 'D') return L.dirWords[t.dir]; if (c === 'E') return L.dirWords[t.ldir]; if (c === 'p') return saint;
      return '%' + c;
    });
  }
  function regionMul(e?: any, dia?: any): any { if (dia == null || e.grp == null) return 1; const v = dia.w[e.grp]; return v == null ? 1 : v; }
  M.partKeys = function (e?: any, cls?: any): any {
    if (cls == null) return [];
    e.wkeys = e.wkeys || {};
    let c = e.wkeys[cls];
    if (c == null) {
      const seen: any = {}; c = [];
      const txt = e.k || e.text || '';
      for (const k of M.NW.keys(txt, cls)) if (!seen[k]) { seen[k] = true; c.push(k); }
      for (const k of M.NW.keys('Zz' + M.NW.lower(txt), cls)) if (!seen[k]) { seen[k] = true; c.push(k); }
      // (a stem's root, NEXT_PHASE_BRIEF 50 item 2)
      if (e.form == null && e.k == null && e.kind === 'stem' && txt.length >= 2) {
        const r = '^' + M.NW.fold(lowerAll(txt));
        if (!seen[r]) { seen[r] = true; c.push(r); }
      }
      c.sort(cmpStr);
      e.wkeys[cls] = c;
    }
    return c;
  };
  // (NEXT_PHASE_BRIEF 60 / 61: s53 without the +60 entries, s53 and s60 without the +61 ones)
  M.ruleOut = function (ctx?: any, e?: any): any {
    const f = e.flags || {};
    if (f['61'] && ctx.rules !== 's61') return true;
    return ctx.rules === 's53' && f['60'] === true;
  };
  function rankParts(ctx?: any, list?: any, x?: any, t?: any, which?: any, useTbl?: any, useK?: any): any {
    const out: any = [];
    list.forEach((e?: any, i0?: any) => {
      const i = i0 + 1;
      let [f, bt] = M.fit(e, x);
      let blk = false;
      if (M.climateVeto(ctx, e)) f = -1e6;
      // (the s53 rules, the lab's comparison: without the entries NEXT_PHASE_BRIEF 60 added, +60)
      if (M.ruleOut(ctx, e)) { f = -1e6; blk = true; }
      if (e.flags.p && f > 0 && !t.quiet) f = f * C.PERS_K;
      if (t.quiet && M.ideaOf(e.river ? 'river' : e.main)) f = f - C.QUIET_PEN;
      if (e.boost) f = f + e.boost;
      // (NEXT_PHASE_BRIEF 53 Part B: the layer, the climate's forms, water on a dry map, the settler group)
      if (t.layer) f = f + M.layerAdj(ctx.L, e, t.layer);
      if (ctx.cl && e.raw && ctx.cl.boost[e.raw]) f = f + C.CLIMATE_BOOST;
      if (ctx.climate === 'dry' && e.main && M.WATER_TAG[e.main] && (x[e.main] || 0) > 0) f = f + C.DRY_WATER;
      if (e.grp && ctx.cl && ctx.cl.group && e.grp === ctx.cl.group.grp) {
        if (t.glayer === e.grp) f = f + C.GLAYER_K; else f = f - C.DIALECT_PEN;
      }
      if (t.dialect && e.grp && (t.dialect.w[e.grp] == null ? 1 : t.dialect.w[e.grp]) < 1) f = f - C.DIALECT_PEN;
      let m = regionMul(e, t.dialect);
      if (which === 's') m = Math.sqrt(m);
      if (f > 0) f = f * m; else f = f - 0.1 * (1 - m);
      f = f + 0.15 * (m - 1);
      if (e.rare) f = f + (t.character ? C.RARE_ON : -C.RARE_OFF);
      f = f - (useTbl[e.k || e.text] || 0) * useK;
      if (t.blocked && Object.keys(t.blocked).length > 0) {
        for (const k of M.partKeys(e, t.cls)) if (t.blocked[k]) { f = f - C.BUDGET_PEN; break; }
      }
      // (NEXT_PHASE_BRIEF 60: opaque parts far down and capped per map; flavor parts only on the planned flavor towns)
      if (ctx.opaqueCap != null && M.opaque(e)) {
        if (ctx.opaqueN >= ctx.opaqueCap) { f = -1e6; blk = true; } else f = f - C.OPAQUE_PEN;
      }
      if (ctx.flavorCap != null && M.flavorPart(e)) {
        if (t.flavor && ctx.flavorN < ctx.flavorCap) f = f + C.FLAVOR_ON; else { f = -1e6; blk = true; }
      }
      if (ctx.flavorCap != null && e.grp && ctx.cl && ctx.cl.group && e.grp === ctx.cl.group.grp &&
        (t.glayer !== e.grp || ctx.flavorN >= ctx.flavorCap)) { f = -1e6; blk = true; }
      f = f + C.JITTER * unit(ctx.seed, which, t.id || 0, i);
      out.push({ e, f, bt, i, blk });
    });
    out.sort((a?: any, c?: any) => a.f !== c.f ? c.f - a.f : a.i - c.i);
    return out;
  }
  M.rankParts = rankParts;
  function family(tag?: any): any {
    if (tag == null) return null;
    let p = M.PARENT[tag];
    while (p && p[0]) { tag = p[0]; p = M.PARENT[tag]; }
    return tag;
  }
  M.family = family;
  function cmpStr(a?: any, c?: any): any { return a < c ? -1 : (a > c ? 1 : 0); }

  // ---------------------------------------------------------------- roots and affix patterns (NEXT_PHASE_BRIEF 50)
  const patEsc = (ch: any) => /[\^$()%.\[\]*+\-?]/.test(ch) ? '%' + ch : ch;
  // a Lua pattern (the export's subset: literal bytes, %x escapes, .+) as a JS RegExp
  function luaPat(p?: any): any {
    let out = '';
    for (let i = 0; i < p.length; i++) {
      const ch = p[i];
      if (ch === '%') { i++; out += p[i].replace(/[.*+?^${}()|[\]\\\/-]/g, '\\$&'); }
      else if (ch === '^' && i === 0) out += '^';
      else if (ch === '$' && i === p.length - 1) out += '$';
      else if (ch === '.') out += '[\\s\\S]';
      else if (ch === '+') out += '+';
      else out += ch.replace(/[.*+?^${}()|[\]\\\/-]/g, '\\$&');
    }
    return new RegExp(out);
  }
  function rootIndex(L?: any, r61?: any): any {
    const key = r61 ? 'rootIdx61' : 'rootIdx';
    if (L[key]) return L[key];
    const R: any = { stems: [], suf: {}, pre: [], words: {}, pats: [], cache: {}, n: 0 };
    for (const e of L.specs) {
      const t = e.k || e.text;
      if ((e.kind === 'stem' || e.kind === 'noun') && typeof t === 'string' && t.indexOf(' ') < 0 && t.length >= 2) R.stems.push(lowerAll(t));
    }
    R.stems.sort((a?: any, c?: any) => a.length !== c.length ? c.length - a.length : cmpStr(a, c));
    for (const g of L.gens) {
      const t = lowerAll(g.text || '');
      if (g.form === 'suf') R.suf[t] = true;
      else if (g.form === 'pre' || g.form === 'hyph') R.pre.push(t.replace(/-$/, ''));
      for (const w of (t.match(/[^ \-']+/g) || [])) R.words[w] = true;
    }
    for (const a of L.affixes) {
      if (a.flags['61'] && !r61) continue;
      const tpl = lowerAll(a.text || '');
      const lit = tpl.replace(/%[A-Za-z]/g, ' ');
      // (NEXT_PHASE_BRIEF 61: an evocative or industry name's words keep their roots)
      if (!(a.flags.g || a.flags.i)) for (const w of (lit.match(/[^ \-']+/g) || [])) R.words[w] = true;
      const fm = /[^ \-']+/.exec(lit);
      if (fm) {
        const lp = '^' + tpl.replace(/%[A-Za-z]/g, '\x01').split('').map(patEsc).join('').replace(/\x01/g, '.+') + '$';
        R.pats.push({ re: luaPat(lp), fam: '%' + fm[0], rare: a.rare ? ('%!' + tpl.replace(/\s+/g, '_')) : null,
          lit: lit.replace(/[\s\-']/g, '').length });
      }
    }
    L[key] = R;
    return R;
  }
  M.rootIndex = rootIndex;
  function wordRoot(R?: any, w?: any): any {
    if (R.words[w] || M.NW.STOP[w]) return null;
    for (const p of R.pre) {
      if (p.length >= 2 && w.length > p.length + 2 && w.slice(0, p.length) === p) {
        const r = wordRoot(R, w.slice(p.length));
        if (r) return r;
      }
    }
    for (let i = 0; i < R.stems.length; i++) {
      if (i + 1 > 4000) break;
      const st = R.stems[i];
      if (w.length >= st.length && w.slice(0, st.length) === st) {
        const rem = w.slice(st.length);
        if ((rem === '' || rem === 's' || rem === 'es') && st.length >= 3) return st;
        if (rem !== '' && R.suf[rem]) return st;
        if (st.length >= 4 && rem.length >= 2) return st;
      }
    }
    return null;
  }
  M.extraKeys = function (L?: any, name?: any, skipWords?: any, r61?: any): any {
    if (L == null || L.script || typeof name !== 'string') return [];
    const R = rootIndex(L, r61);
    const c = R.cache[name];
    if (c && skipWords == null) return c;
    const out: any = [], seen: any = {};
    const low = lowerAll(name);
    for (const w of (low.match(/[^ \-']+/g) || [])) {
      if (w.length >= 2 && !(skipWords && skipWords[w])) {
        let r = wordRoot(R, w);
        if (r) { r = '^' + M.NW.fold(r); if (!seen[r]) { seen[r] = true; out.push(r); } }
      }
    }
    let rareKey: any = null, rareLit = -1;
    for (const p of R.pats) {
      if (p.re.test(low)) {
        if (!seen[p.fam]) { seen[p.fam] = true; out.push(p.fam); }
        if (p.lit > rareLit) { rareKey = p.rare; rareLit = p.lit; }
      }
    }
    if (rareKey && !seen[rareKey]) { seen[rareKey] = true; out.push(rareKey); }
    out.sort(cmpStr);
    if (skipWords == null) {
      if (R.n >= C.ROOT_CACHE) { R.cache = {}; R.n = 0; }
      R.cache[name] = out; R.n++;
    }
    return out;
  };
  M.attachExtra = function (B?: any, lang?: any, features?: any, r61?: any): any {
    const L = lang ? M.lang(lang) : null;
    if (B == null || L == null || L.script) return B;
    B.features = features;
    let cache: any = {}, n = 0;
    B.extra = function (name?: any): any {
      let c = cache[name];
      if (c == null) {
        c = M.extraKeys(L, name, B.features, r61);
        if (n >= C.ROOT_CACHE) { cache = {}; n = 0; }
        cache[name] = c; n++;
      }
      return c;
    };
    return B;
  };

  // ---------------------------------------------------------------- the feature qualifier rule (NEXT_PHASE_BRIEF 50)
  function featureUses(ctx?: any, t?: any, c?: any, a?: any): any {
    const out: any = [];
    const whole = a != null && !a.hasS;
    const low = (x: any) => typeof x === 'string' ? lowerAll(x) : null;
    if (a) {
      if ((a.needR || a.needT) && t.river) out.push([low(t.river.s || t.river.n), true, whole]);
      if (a.needM && t.mount) out.push([low(t.mount.s), true, whole]);
      if (a.needK && t.lake) out.push([low(t.lake.s || t.lake.n), true, whole]);
      if (a.needB && t.bay) out.push([low(t.bay.s), true, whole]);
    }
    const se = c && c.s && c.s.e;
    if (se) {
      const st = low(se.k || se.text);
      if (se.river) out.push([st, true, false]);
      else if (st && ctx.featWords && ctx.featWords[st]) out.push([st, false, false]);
    }
    return out;
  }
  function featureOk(ctx?: any, uses?: any): any {
    for (const u of uses) {
      const f = u[0] != null ? ctx.featUse[u[0]] : null;
      if (f) {
        if (f.n >= C.FEAT_MAX || !u[1] || f.plain > 0 || (u[2] && f.whole > 0)) { M.misfit(ctx, u[0], 'feature'); return false; }
      }
    }
    return true;
  }
  function featureTake(ctx?: any, uses?: any): any {
    for (const u of uses) {
      if (u[0] != null) {
        const f = ctx.featUse[u[0]] || { n: 0, plain: 0, whole: 0 };
        f.n++; if (!u[1]) f.plain++; if (u[2]) f.whole++;
        ctx.featUse[u[0]] = f;
      }
    }
  }

  // ---------------------------------------------------------------- name shapes (NEXT_PHASE_BRIEF 53)
  M.SHAPES = PN.SHAPES || ['plain', 'single', 'separate', 'personal', 'article', 'qualifier', 'frame', 'saint', 'whole', 'civic', 'character', 'evoc', 'industry'];
  M.AFFIX_SHAPES = { qualifier: true, frame: true, saint: true, whole: true, civic: true, character: true, evoc: true, industry: true };
  // (NEXT_PHASE_BRIEF 61)
  M.KINDS61 = PN.KINDS61 || { forest: true, secluded: true, coastal: true };
  M.WORDS61 = PN.WORDS61 || {};
  M.IND_FAM_K = PN.IND_FAM_K || {};
  M.WATER_TAG = PN.WATER_TAG || {};
  M.LAYER_SITE = PN.LAYER_SITE || [];
  M.NON_IDEA = PN.NON_IDEA || {};
  M.FUNC_WORDS = PN.FUNC_WORDS || {};
  M.CLAIM_MIN = PN.CLAIM_MIN || {};
  M.FEAT_TAGS = PN.FEAT_TAGS || {};
  M.affixShape = function (a?: any): any {
    if (a.flags.i) a.shape = 'industry';
    else if (a.flags.g && !a.hasS) a.shape = 'evoc';
    else if (a.flags.v) a.shape = 'civic';
    else if (a.needP) a.shape = 'saint';
    else if (a.bare || !a.hasS) a.shape = 'whole';
    else if (a.flags.q) a.shape = 'qualifier';
    else a.shape = 'frame';
    a.mapDir = a.needD === true;
    a.joined = !/[ \-]/.test(a.text || '');
    if (a.shape === 'qualifier') {
      let kind = 'other', dir: any = null;
      for (const p of a.tl) { const t = p[0]; if (t === 'north' || t === 'south' || t === 'east' || t === 'west') { kind = 'compass'; dir = t; break; } }
      if (kind === 'other') {
        for (const p of a.tl) {
          const t = p[0];
          if (t === 'small') { kind = 'small'; break; }
          else if (t === 'big') { kind = 'big'; break; }
          else if (t === 'upper' || t === 'slope' || t === 'hilltop') { kind = 'upper'; break; }
          else if (t === 'lower' || t === 'foot') { kind = 'lower'; break; }
          else if (t === 'new' || t === 'old') { kind = 'age'; break; }
        }
      }
      a.qkind = kind; a.qdir = dir;
    }
    return a.shape;
  };
  M.ideaOf = function (tag?: any): any {
    if (tag == null || M.NON_IDEA[tag]) return null;
    const f = family(tag);
    if (f == null || M.NON_IDEA[f]) return null;
    return f;
  };
  M.ideas = function (sE?: any, gE?: any, aE?: any, twin?: any): any {
    const seen: any = {}; let n = 0;
    const add = (tag: any) => { const f = M.ideaOf(tag); if (f && !seen[f]) { seen[f] = true; n++; } };
    if (aE && !aE.hasS) { add(aE.main); return n; }
    if (sE) add(sE.river ? 'river' : sE.main);
    if (gE) add(gE.main);
    if (aE && !twin) add(aE.main);
    return n;
  };
  M.tokens = function (name?: any): any {
    if (typeof name !== 'string') return 0;
    if (!/[ \-]/.test(name)) return 1;
    let n = 0;
    for (const w of (lowerAll(name).match(/[^ \-]+/g) || [])) if (!M.FUNC_WORDS[w]) n++;
    return Math.max(n, 1);
  };
  function baseShape(L?: any, c?: any, Q?: any): any {
    if (c.shape) return c.shape;
    Q = Q || L.quota;
    const g = c.g.e, s = c.s.e;
    if (g.flags.v) return 'civic';
    if ((g.form === 'after' || g.form === 'before') && Q.separate) return 'separate';
    if (s.flags.p && Q.personal) return 'personal';
    return 'plain';
  }
  M.baseShape = baseShape;
  M.countWords = function (ctx?: any, nm?: any, reserved?: any): any {
    if (ctx.wordAllow == null) return;
    const extra = M.tokens(nm) - 1 - (reserved ? 1 : 0);
    if (extra > 0) ctx.wordExtra += extra;
    ctx.wordN++;
  };
  M.wordsOver = function (ctx?: any, extra?: any): any {
    if (ctx.wordAllow == null || extra <= 0) return false;
    return ctx.wordExtra + extra > ctx.wordAllow * (ctx.wordN + 1) / Math.max(1, ctx.wordTowns) + 0.5;
  };
  const EMPTY_S = newEntry('-'); EMPTY_S.kind = 'stem'; EMPTY_S.x = [];
  const EMPTY_G = newEntry('-'); EMPTY_G.form = 'none'; EMPTY_G.x = [];
  function commonEntry(L?: any, base?: any): any {
    L.commonE = L.commonE || {};
    let e = L.commonE[base];
    if (e == null) { e = newEntry(base); e.kind = 'stem'; e.x = []; e.common = true; L.commonE[base] = e; }
    return e;
  }

  // (NEXT_PHASE_BRIEF 60, ot_placename.opaque / flavorPart / quota60 / siteWord)
  M.RULES = PN.RULES || 's60';
  M.CUE_K = PN.CUE_K || {}; M.SHAPE_K60 = PN.SHAPE_K60 || {}; M.SEP60 = PN.SEP60 || {}; M.WORDS60 = PN.WORDS60 || {};
  M.READ_SKIP = PN.READ_SKIP || {};
  M.opaque = function (e?: any): any { return e != null && e.flags != null && (e.flags.p === true || e.flags.u === true); };
  M.flavorPart = function (e?: any): any { return e != null && e.flags != null && e.flags.n === true; };
  M.quota60 = function (Q?: any, lang?: any): any {
    const out: any = Object.assign({}, Q || {});
    let sum = 0;
    const cueShapes = Object.keys(M.CUE_K).sort();
    for (const sh of cueShapes) {
      const v = out[sh];
      if (v && v > 0) { out[sh] = Math.min(v * M.CUE_K[sh], Math.max(v, C.CUE_CAP)); sum += out[sh]; }
    }
    if (sum > C.CUE_TOTAL) for (const sh of cueShapes) if (out[sh] != null) out[sh] = Math.max(Q[sh], out[sh] * C.CUE_TOTAL / sum);
    for (const sh in M.SHAPE_K60) if (out[sh] != null) out[sh] = out[sh] * M.SHAPE_K60[sh];
    const sep = M.SEP60[lang || ''];
    if (sep != null && out.separate != null) out.separate = Math.max(out.separate, sep);
    return out;
  };
  M.siteWord = function (info?: any, w?: any): any {
    if (!info || typeof info !== 'object') return false;
    const x = M.expandSite(w || {});
    const partOk = (e: any) => {
      if (!e || e.text === '-' || e.tl == null) return false;
      if (e.river) return true;
      if (M.opaque(e) || M.flavorPart(e) || (e.flags && e.flags.c)) return false;
      const t = e.main;
      return t != null && !M.READ_SKIP[t] && (x[t] || 0) >= 0.2;
    };
    if (partOk(info.sE) || partOk(info.gE)) return true;
    const a = info.aE;
    if (a && typeof a === 'object') {
      if (a.needR || a.needT || a.needK || a.needM || a.needB || a.needE) return true;
      if (info.twin == null && partOk(a)) return true;
    }
    return false;
  };
  M.nameTown = function (ctx?: any, t?: any): any {
    const L = ctx.L;
    t.seed = ctx.seed;
    const Q = ctx.quota || L.quota;
    if (t.saints == null && ctx.cl) t.saints = ctx.cl.saints;
    const x = M.expandSite(t.w || {});
    t.dialect = t.dialect || M.dialectAt(ctx, t.x, t.y);
    let shape = t.shape == null ? null : t.shape;
    const strict = shape != null && t.dialect != null && !t.dialect.hybrid;
    let specList = t.fixedSpec ? [t.fixedSpec] : (t.specList || L.specs);
    if (t.specs && !t.fixedSpec) specList = t.specs.concat(specList);
    if (ctx.budget) { t.cls = ctx.budget.cls; t.blocked = M.NW.blockedKeys(ctx.budget, t.x, t.y, t.skipWords); }
    const gens = rankParts(ctx, t.gens || L.gens, x, t, 'g', ctx.genUse, C.USE_GEN);
    const specs = rankParts(ctx, specList, x, t, 's', ctx.specUse, C.USE_SPEC);
    const count = ctx.plan ? ctx.plan.count : {};
    ctx.shapeUse = ctx.shapeUse || {};
    let need = shape != null && M.AFFIX_SHAPES[shape] === true;
    const search = (ns?: any, ng?: any) => {
      const cands: any = [];
      for (let si = 0; si < Math.min(ns, specs.length); si++) {
        const s = specs[si];
        for (let gi = 0; gi < Math.min(ng, gens.length); gi++) {
          const g = gens[gi];
          let base = (!s.blk && !g.blk) ? M.join(L, s.e, g.e, strict) : null;
          // (+e, NEXT_PHASE_BRIEF 60: no "Lake Shady")
          if (base && g.e.flags.e && s.e.flags.a && ctx.rules !== 's53') base = null;
          if (base && g.e.flags.v && t.noCivic) base = null;
          if (base && M.wellFormed(L, base)) {
            let sc = g.f + C.SPEC_K * s.f, pair = 0;
            if (s.bt && g.bt && s.bt !== g.bt && family(s.bt) !== family(g.bt) && s.f > 0.3 && g.f > 0.3) { sc = sc + C.PAIR_BONUS; pair = C.PAIR_BONUS; }
            // (NEXT_PHASE_BRIEF 60: a pair that names no feature, on a town that isn't quiet)
            if (ctx.opaqueCap != null && shape != null && !t.quiet && M.ideas(s.e, g.e) === 0) sc = sc - C.LITERAL_PEN;
            const c: any = { base, s, g, sc, pair };
            if (shape != null) {
              const bs = baseShape(L, c, Q);
              if ((bs === 'separate' || bs === 'personal' || bs === 'civic') && (ctx.shapeUse[bs] || 0) >= (count[bs] || 0)) c.sc = c.sc - C.SHAPE_OVER;
              else if (bs === 'separate' && ctx.rules !== 's53' && !need) c.sc = c.sc + C.SEP_BONUS;
              if (shape === 'character' && M.tokens(base) > 1) c.sc = c.sc - C.SHAPE_OVER;
              if (ctx.wordAllow != null && !need && M.tokens(base) > 1 && M.wordsOver(ctx, M.tokens(base) - 1)) c.sc = c.sc - C.SHAPE_OVER;
            }
            cands.push(c);
          }
        }
      }
      cands.sort((a?: any, c?: any) => a.sc !== c.sc ? c.sc - a.sc : cmpStr(a.base, c.base));
      return cands;
    };
    const final = (full: any) => (L.script === 'kanji' && !t.noSuffix) ? (full + b('市')) : full;
    const within = (nm?: any, skip?: any) => {
      if (ctx.climate) { const bad = M.wordMisfit(nm, ctx.climate, M.CLS_OF_GEN[ctx.lang] || ctx.lang); if (bad) { M.misfit(ctx, bad, ctx.climate); return false; } }
      return M.NW.allow(ctx.budget, nm, t.x, t.y, skip || t.skipWords);
    };
    const sized = (nm?: any, c?: any, a?: any) => {
      if (shape == null) return true;
      const k = M.tokens(nm);
      if (a && k > 2 && shape !== 'character' && M.wordsOver(ctx, k - 2)) return false;
      // (NEXT_PHASE_BRIEF 61: a character town's form names its kind on top)
      const extraIdea = (shape === 'character' && ctx.rules === 's61') ? 1 : 0;
      return k <= C.MAX_TOKENS && M.ideas(c.s.e, c.g.e, a) <= C.MAX_IDEAS + extraIdea;
    };
    const affixOk = (a?: any, c?: any) => {
      if (a.flags.k && shape !== 'character') return false;
      // (NEXT_PHASE_BRIEF 61: evocative and industry names only on their shapes)
      if ((a.shape === 'evoc' || a.shape === 'industry') && shape !== a.shape) return false;
      if (shape === 'character') {
        const set = t.charKind ? (ctx.charForms || L.charForms)[t.charKind] : null;
        return set != null && set[a.raw || ''] === true && !a.mapDir && (M.tokens(c.base) === 1 || ctx.rules === 's61');
      }
      if (shape === 'evoc') return a.shape === 'evoc' && M.gateOk(a, t.wraw, t.facts);
      if (shape === 'industry') return a.shape === 'industry' && t.ind != null && a.fam === t.ind.fam;
      if (a.flags.v && t.noCivic) return false;
      if (shape == null) return true;
      if (a.shape !== shape || a.mapDir) return false;
      if (shape === 'qualifier') {
        if (!Q.separate && M.tokens(c.base) > 1) return false;
        if (t.qualMode === 'river') return a.qkind === t.qualKind && !a.joined && c.s.e.river === true;
        return a.qkind === 'age' || a.qkind === 'other' || (a.joined && (a.qkind === 'upper' || a.qkind === 'lower'));
      }
      if (shape === 'frame') {
        if (t.frameFeat && !(a.needR || a.needT || a.needK || a.needM || a.needB)) return false;
        if ((ctx.affUse[a.k || a.text] || 0) >= ctx.frameCap) return false;
        if ((a.needR || a.needT) && t.river && ctx.riverFrame[t.river.s || t.river.n]) return false;
        if (M.tokens(c.base) > 1) return false;
        if ((a.needR || a.needT) && t.river && t.river.s && lowerAll(c.base).indexOf(lowerAll(t.river.s)) >= 0) return false;
      }
      return true;
    };
    const choose = (cands?: any, anyAffix?: any, maxC?: any, needA?: any) => {
      const cost = t.character ? C.AFFIX_COST_CH : C.AFFIX_COST;
      for (let ci = 0; ci < cands.length; ci++) {
        if (ci + 1 > (maxC || 40)) break;
        const c = cands[ci];
        let bestA: any = null, bestS = (anyAffix || needA) ? -Infinity : 0, bestN: any = null;
        if (!t.noAffix && (shape == null || needA)) {
          L.affixes.forEach((a?: any, ai0?: any) => {
            const ai = ai0 + 1;
            if (!affixOk(a, c) || M.ruleOut(ctx, a)) return;
            const [raw, abt] = M.fit(a, x);
            let af = raw;
            if (M.climateVeto(ctx, a)) af = -1e6;
            if (a.rare) af = af + (t.character ? C.RARE_ON : -C.RARE_OFF);
            af = af - cost + 0.1 * unit(ctx.seed, 'a', t.id || 0, ai);
            af = af - (ctx.affUse[a.k || a.text] || 0) * C.USE_AFFIX;
            const fam = family(abt);
            const clash = a.cls != null && (a.cls === c.s.e.cls || a.cls === c.g.e.cls);
            const whole = !a.hasS;
            const fits = raw > 0 || a.shape === 'saint' || shape === 'character' || shape === 'industry';
            const okWhole = whole && (t.character || af >= C.FULL_MIN || (needA && fits));
            if (af > bestS && !clash && (a.hasS || okWhole) && (!needA || fits) &&
              (whole || (!M.repeats(a, c.base) && !(fam && fam === family(c.g.bt) && fam !== 'any')))) {
              const full = fillAffix(L, a, c.base, t);
              if (full && M.chars(full) <= C.MAX_FULL && M.free(ctx, final(full)) && sized(final(full), c, a) &&
                featureOk(ctx, featureUses(ctx, t, c, a)) && within(final(full), c.skip)) { bestA = a; bestS = af; bestN = full; }
            }
          });
        }
        if (bestA) return [c, bestA, bestN, bestS];
        if (!anyAffix && !needA && M.free(ctx, final(c.base)) && sized(final(c.base), c, null) &&
          featureOk(ctx, featureUses(ctx, t, c, null)) && within(final(c.base), c.skip)) return [c, null, c.base, 0];
      }
      return [null];
    };
    const singleCands = () => {
      const out: any = [];
      if (L.script) return out;
      for (const g of gens) {
        if (out.length >= 30) break;
        if (g.e.flags.o && g.f > -1e5) {
          const base = M.capFirst(g.e.text);
          if (M.wellFormed(L, base)) out.push({ base, s: { e: EMPTY_S, f: 0 }, g, sc: g.f, shape: 'single' });
        }
      }
      return out;
    };
    const articleCands = () => {
      const out: any = [];
      const A = L.articles;
      if (!A || typeof A !== 'object' || L.script) return out;
      for (const g of gens) {
        if (out.length >= 30) break;
        const e = g.e;
        if (e.gender && A[e.gender] && (e.form === 'before' || e.form === 'pre') && g.f > -1e5) {
          const base = (A.el && /^[AEIOUaeiou]/.test(e.text)) ? A.el + e.text : A[e.gender] + ' ' + e.text;
          out.push({ base, s: { e: EMPTY_S, f: 0 }, g, sc: g.f, shape: 'article' });
        }
      }
      return out;
    };
    const frameBases = () => {
      const out: any = [];
      L.common.forEach((bb?: any, i0?: any) => {
        out.push({ base: bb, s: { e: commonEntry(L, bb), f: 0 }, g: { e: EMPTY_G, f: 0 }, sc: C.JITTER * unit(ctx.seed, 'cb', t.id || 0, i0 + 1), common: true });
      });
      (ctx.rules !== 's53' ? [] : (ctx.plainBases || [])).forEach((pb?: any, i0?: any) => {
        if (!pb.framed) out.push({ base: pb.base, s: { e: commonEntry(L, pb.base), f: 0 }, g: { e: EMPTY_G, f: 0 },
          sc: 0.15 + C.JITTER * unit(ctx.seed, 'rb', t.id || 0, i0 + 1), reuse: pb, skip: pb.keys });
      });
      out.sort((a?: any, c?: any) => a.sc !== c.sc ? c.sc - a.sc : cmpStr(a.base, c.base));
      return out;
    };
    let top: any = null, wideUsed = false;
    const attempt = (needA: any) => {
      top = search(C.TOP_SPEC, C.TOP_GEN);
      let r = choose(top, false, null, needA);
      if (r[0] == null) {
        const wide = search(C.WIDE_SPEC, C.WIDE_GEN); wideUsed = true; top = wide;
        r = choose(wide, false, needA ? C.NEED_WIDE : C.WIDE_SPEC * C.WIDE_GEN, needA);
        if (r[0] == null && shape == null) r = choose(wide, true, 200);
        if (r[0] == null && ctx.budget && !t.strictBudget && !needA) {
          const bb = ctx.budget;
          ctx.budget = null;
          r = choose(wide, false, C.WIDE_SPEC * C.WIDE_GEN);
          ctx.budget = bb;
          if (r[0]) bb.over = (bb.over || 0) + 1;
        }
      }
      return r;
    };
    let first: any = null;
    if (shape === 'single') first = singleCands();
    else if (shape === 'article') first = articleCands();
    else if (shape === 'frame' && L.common.length > 0) first = frameBases();
    let r: any = [null];
    // (NEXT_PHASE_BRIEF 60: a frame on the town's named feature first, "Oakhaven-on-Blackmere"; then the common bases)
    if (shape === 'frame' && ctx.rules !== 's53') { t.frameFeat = true; r = attempt(need); t.frameFeat = null; }
    if (r[0] == null) {
      if (first) { top = first; r = choose(first, false, 400, need); }
      else r = attempt(need);
    }
    // (NEXT_PHASE_BRIEF 61: a character town always carries its kind: over the word budget before a plain name)
    if (r[0] == null && shape === 'character' && ctx.rules === 's61' && ctx.budget) {
      const bb = ctx.budget;
      ctx.budget = null;
      r = attempt(need);
      ctx.budget = bb;
      if (r[0]) bb.over = (bb.over || 0) + 1;
    }
    if (r[0] == null && shape != null && shape !== 'plain') {
      ctx.shapeMiss = (ctx.shapeMiss || 0) + 1;
      shape = 'plain'; need = false;
      r = attempt(false);
    }
    let [c, a, nm, as] = r;
    if (c == null) return [null, 'noUnique'];
    nm = final(nm);
    M.take(ctx, nm);
    const opq = M.opaque(c.s.e) || M.opaque(c.g.e);
    const grp0 = ctx.cl && ctx.cl.group ? ctx.cl.group.grp : null;
    const flv = M.flavorPart(c.s.e) || M.flavorPart(c.g.e) || M.flavorPart(a) || (grp0 != null && (c.s.e.grp === grp0 || c.g.e.grp === grp0));
    if (opq) ctx.opaqueN++;
    if (flv) ctx.flavorN++;
    featureTake(ctx, featureUses(ctx, t, c, a));
    M.NW.add(ctx.budget, nm, t.x, t.y, c.skip || t.skipWords);
    const sk = c.s.e.k || c.s.e.text, gk = c.g.e.k || c.g.e.text;
    ctx.specUse[sk] = (ctx.specUse[sk] || 0) + 1;
    ctx.genUse[gk] = (ctx.genUse[gk] || 0) + 1;
    if (a) ctx.affUse[a.k || a.text] = (ctx.affUse[a.k || a.text] || 0) + 1;
    let got = (a && a.shape) || baseShape(L, c, Q);
    if (a && shape === 'character') got = 'character';
    if (t.shape != null) {
      ctx.shapeUse[got] = (ctx.shapeUse[got] || 0) + 1;
      M.countWords(ctx, nm, need);
      if (a && a.shape === 'frame' && (a.needR || a.needT) && t.river) ctx.riverFrame[t.river.s || t.river.n] = true;
      if (c.reuse) c.reuse.framed = true;
      if (a == null && got !== 'single' && got !== 'article' && !L.script) {
        ctx.plainBases = ctx.plainBases || [];
        if (ctx.plainBases.length < C.MAX_TOWNS) ctx.plainBases.push({ base: c.base, keys: ctx.budget ? M.NW.budgetKeys(ctx.budget, c.base) : [] });
      }
    }
    const feat = c.g.bt || c.s.bt || '-';
    return [nm, { spec: sk, gen: gk, affix: a ? (a.k || a.text) : null, whole: a != null && !a.hasS, feature: feat, specTag: c.s.bt, genTag: c.g.bt,
      score: c.sc + (as || 0), dialect: t.dialect ? t.dialect.name : null, base: c.base, sE: c.s.e, gE: c.g.e, aE: a,
      shape: got, quiet: M.ideas(c.s.e, c.g.e, a) === 0 && !(ctx.rules === 's61' && (got === 'evoc' || got === 'industry' || got === 'character')), reuse: c.reuse ? c.reuse.base : null, hybrid: t.dialect != null && t.dialect.hybrid === true,
      layer: t.layer, charKind: t.charKind, opaque: opq, flavor: flv,
      ind: (got === 'industry' && t.ind) ? t.ind.fam : null, gate: got === 'evoc' ? M.gateText(a, t.wraw, t.facts) : null,
      dbg: { sF: c.s.f, gF: c.g.f, pair: c.pair || 0, affixScore: as || 0, wide: wideUsed, x,
        alts: (top || []).slice(0, 10).map((q: any) => ({ base: q.base, sc: q.sc, s: q.s.e.k || q.s.e.text, g: q.g.e.k || q.g.e.text })) } }];
  };

  M.withCues = function (w?: any, cue?: any): any {
    const out = Object.assign({}, w || {});
    if (cue && cue.w) for (const k in cue.w) { const v = cue.w[k]; if (M.TAG_INDEX[k] && typeof v === 'number' && v > (out[k] || 0)) out[k] = Math.min(1, v); }
    return out;
  };
  M.rankOf = M.ranked;
  M.CLS_OF_GEN = PN.CLS_OF_GEN || {};
  M.featName = function (ctx?: any, kind?: any, grp?: any): any {
    const D = ctx.L.data;
    if (ctx.L.script) return null;
    const stems = split(kind === 'mount' ? D.peaks : (D.bays || D.lakes), '|');
    let form = kind === 'mount' ? D.peakForm : D.bayForm;
    if (kind === 'mount' && grp && D.peakFormBy && typeof D.peakFormBy === 'object' && D.peakFormBy[grp]) form = D.peakFormBy[grp];
    if (stems.length === 0 || form == null) return null;
    ctx.featNames = ctx.featNames || {};
    const start = hash(ctx.seed, 'feat', kind) % stems.length;
    for (let i = 0; i < stems.length; i++) {
      const stem = stems[(start + i) % stems.length];
      const full = form.replace(/_/g, ' ').replace(/%s/g, () => stem);
      if (!ctx.featNames[stem] && M.free(ctx, full) && M.free(ctx, stem)) { ctx.featNames[stem] = true; return { n: full, s: stem }; }
    }
    return null;
  };
  // ---------------------------------------------------------------- the map's plan (NEXT_PHASE_BRIEF 53)
  const vetoed = (ctx?: any, e?: any) => {
    const c = ctx && ctx.climate;
    if (c == null) return false;
    if (ctx.cl && e.raw && ctx.cl.veto[e.raw]) return true;
    for (const p of (e.tl || [])) if (p[1] >= CLD.VETO_MIN && M.vetoTag(c, p[0])) return true;
    return false;
  };
  // (NEXT_PHASE_BRIEF 61) an evocative name's gate on the town's reading (wraw, before rarity) and facts
  M.gateOk = function (a?: any, wraw?: any, facts?: any): any {
    if (!a.gate || a.gate.length === 0) return !a.flags.g;
    wraw = wraw || {};
    for (const g of a.gate) {
      let okG = false;
      for (const tag of g.tags) {
        if (tag === 'lakes2') { if ((Number(facts && facts.lakes) || 0) >= 2) okG = true; }
        else if ((Number(wraw[tag]) || 0) >= (g.min != null ? g.min : C.EVOC_MIN)) okG = true;
      }
      if (!okG) return false;
    }
    return true;
  };
  M.gateText = function (a?: any, wraw?: any, facts?: any): any {
    if (!a || !a.gate) return '-';
    const parts: any = [];
    for (const g of a.gate) {
      let bt: any = null, bv = -1;
      for (const tag of g.tags) {
        const v = tag === 'lakes2' ? (Number(facts && facts.lakes) || 0) : (Number((wraw || {})[tag]) || 0);
        if (v > bv) { bt = tag; bv = v; }
      }
      if (bt) parts.push(bt + ':' + bv.toFixed(2));
    }
    return parts.length ? parts.join(',') : '-';
  };
  M.fillable = function (L?: any, a?: any, q?: any): any {
    if (a.needR && !(q.river && q.river.n)) return false;
    if (a.needT && !(q.river && q.river.s)) return false;
    if (a.needK && !(q.lake && q.lake.n)) return false;
    if (a.needM && !(q.mount && q.mount.s)) return false;
    if (a.needB && !(q.bay && q.bay.s)) return false;
    if (a.needE && !(q.ldir && L.dirWords[q.ldir])) return false;
    if (a.needD) return false;
    if (a.needP && (q.saints || L.saints).length === 0) return false;
    return true;
  };
  M.featureGrants = function (ctx?: any, list?: any, ws?: any, feats?: any): any {
    const grants: any = {}, leftList: any = []; let left = 0, maxCap = 1;
    for (const t of list) if ((Number(t.cap) || 0) > maxCap) maxCap = Number(t.cap);
    const idOf = (i: any) => Number(list[i].id) || 0;
    for (const F of feats) {
      const tags = M.FEAT_TAGS[F.kind] || [];
      const cl: any = [], tops: any = {};
      for (const i of F.members) {
        let best = 0, bt: any = null;
        for (const tag of tags) { const v = (ws[i][tag] || 0) * (M.SPEC[tag] || 1); if (v > best) { best = v; bt = tag; } }
        cl.push({ i, v: best, tag: bt });
        if (bt) tops[bt] = (tops[bt] || 0) + 1;
      }
      for (const e of cl) {
        const uniq = e.tag ? 1 / tops[e.tag] : 0;
        const size = 0.6 + 0.4 * Math.min(1, (Number(list[e.i].cap) || 0) / maxCap);
        e.c = e.v * uniq * size;
      }
      cl.sort((a?: any, c?: any) => a.c !== c.c ? c.c - a.c : idOf(a.i) - idOf(c.i));
      const lim = clamp(floor(F.members.length / C.FEAT_PER + 0.5), 1, C.FEAT_CAP);
      let n = 0;
      for (const e of cl) {
        if (n < lim && e.c > 0) { grants[e.i] = grants[e.i] || {}; grants[e.i][F.kind] = n === 0 ? 'first' : 'second'; n++; }
        else if (e.c > 0) { left++; leftList.push({ i: e.i, kind: F.kind }); }
      }
    }
    return [grants, left, leftList];
  };
  function twinForms(L?: any): any {
    if (L.twinF) return L.twinF;
    const F: any = {};
    for (const a of L.affixes) {
      if (a.shape === 'qualifier' && !(a.needR || a.needT || a.needK || a.needM || a.needB || a.needE || a.needP)) {
        const k = a.qkind === 'compass' ? a.qdir : a.qkind;
        if (['upper', 'lower', 'small', 'big', 'north', 'south', 'east', 'west'].indexOf(k) >= 0) (F[k] = F[k] || []).push(a);
      }
    }
    L.twinF = F;
    return F;
  }
  M.twinForms = twinForms;
  const dirFrom = (dx?: any, dy?: any) => Math.abs(dx) >= Math.abs(dy) ? (dx >= 0 ? 'east' : 'west') : (dy >= 0 ? 'north' : 'south');
  M.dirFrom = dirFrom;
  // settlement layers (NEXT_PHASE_BRIEF 53 Part B, ot_placename.oldness / layers / yearLayer)
  M.oldness = function (t?: any, w?: any, maxCap?: any): any {
    let site = 0;
    for (const p of M.LAYER_SITE) { const v = Math.min(1, Number((w || {})[p[0]]) || 0) * p[1]; if (v > site) site = v; }
    const size = Math.min(1, (Number(t.cap) || 0) / Math.max(1, Number(maxCap) || 1));
    return [C.LAYER_CAP_K * size + (1 - C.LAYER_CAP_K) * site + (t.character ? 0.1 : 0), site, size];
  };
  M.layers = function (list?: any, ws?: any, year?: any): any {
    const N = list.length, out: any = {}, n: any = { old: 0, mid: 0, late: 0 };
    if (N === 0) return [out, n];
    let maxCap = 1;
    for (const t of list) if ((Number(t.cap) || 0) > maxCap) maxCap = Number(t.cap);
    const sc = list.map((t?: any, i?: any) => ({ i, v: M.oldness(t, ws[i], maxCap)[0], id: Number(t.id) || 0 }));
    sc.sort((a?: any, c?: any) => a.v !== c.v ? c.v - a.v : a.id - c.id);
    const late = (typeof year === 'number' && year >= 1900) ? C.LAYER_LATE_1900 : C.LAYER_LATE;
    const nOld = floor(N * C.LAYER_OLD + 0.5);
    const nLate = Math.min(N - nOld, floor(N * late + 0.5));
    sc.forEach((e?: any, k0?: any) => {
      const k = k0 + 1;
      const lay = k <= nOld ? 'old' : (k > N - nLate ? 'late' : 'mid');
      out[e.i] = lay; n[lay]++;
    });
    return [out, n];
  };
  M.yearLayer = (year: any) => typeof year !== 'number' ? null : (year >= C.YEAR_LATE ? 'late' : 'mid');
  M.planShapes = function (ctx?: any, list?: any, ws?: any, qs?: any, rsys?: any): any {
    const L = ctx.L, N = list.length;
    const Q = ctx.quota || L.quota;
    const P: any = { shape: {}, count: {}, used: {}, quiet: {}, qual: {}, twinOf: {}, twins: [], anchor: {} };
    const forms: any = { saint: 0, article: 0, single: 0 };
    const saints = (ctx.cl && ctx.cl.saints) || L.saints;
    for (const a of L.affixes) if (a.shape === 'saint' && !a.flags.k) forms.saint += a.hasS ? N : saints.length;
    for (const g of L.gens) {
      if (g.flags.o) forms.single++;
      if (g.gender && L.articles && typeof L.articles === 'object' && L.articles[g.gender] && (g.form === 'before' || g.form === 'pre')) forms.article++;
    }
    for (const sh of M.SHAPES) {
      const share = Q[sh] || 0;
      if (share > 0) {
        let n = floor(N * share + draw(ctx.seed, 4, sh));
        n = Math.max(0, Math.min(n, floor(N * (share + C.SHAPE_SLACK))));
        if (forms[sh] != null) n = Math.min(n, forms[sh]);
        P.count[sh] = n;
      }
    }
    const taken: any = {};
    const free = (i: any) => !taken[i] && !list[i].keep;
    const xs = ws.map((w: any) => M.expandSite(w));
    const idOf = (i: any) => Number(list[i].id) || 0;
    const byClaim = (a?: any, c?: any) => a.c !== c.c ? c.c - a.c : idOf(a.i) - idOf(c.i);
    const affixClaim = (i?: any, sh?: any, filter?: any) => {
      const q = qs[i]; let best = -Infinity, bestA: any = null;
      L.affixes.forEach((a?: any, ai0?: any) => {
        if (a.shape === sh && !a.mapDir && !a.flags.k && !(a.flags.v && q.noCivic) && (filter == null || filter(a)) &&
          !M.ruleOut(ctx, a) && M.fillable(L, a, q) && !vetoed(ctx, a)) {
          let f = M.fit(a, xs[i])[0];
          if (a.rare) f = f + (list[i].character ? C.RARE_ON : -C.RARE_OFF);
          if (q.layer) f = f + M.layerAdj(L, a, q.layer);
          f = f + 0.05 * unit(ctx.seed, 'claim', idOf(i), ai0 + 1);
          if (f > best) { best = f; bestA = a; }
        }
      });
      return [best, bestA];
    };
    const hand = (sh?: any, cands?: any, cap?: any, onTake?: any) => {
      cands.sort(byClaim);
      let n = 0;
      for (const e of cands) {
        if (n >= cap) break;
        if (free(e.i) && (onTake == null || onTake(e))) { taken[e.i] = true; P.shape[e.i] = sh; n++; }
      }
      P.used[sh] = (P.used[sh] || 0) + n;
      return n;
    };
    const minOf = (i?: any, sh?: any) => (list[i].character && (sh === 'whole' || sh === 'frame')) ? C.CLAIM_MIN_CH : (M.CLAIM_MIN[sh] || 0);
    // 0. character towns of a kind (NEXT_PHASE_BRIEF 53 Part B)
    const CF = ctx.charForms || L.charForms;
    for (let i = 0; i < N; i++) {
      const k = qs[i].charKind;
      if (free(i) && k && CF[k]) { taken[i] = true; P.shape[i] = 'character'; P.used.character = (P.used.character || 0) + 1; }
    }
    if (ctx.rules === 's61') {
      // 0b. (NEXT_PHASE_BRIEF 61) the industry as a cue, one per family
      let nI = floor(N * C.IND_SHARE + draw(ctx.seed, 12, 'ind'));
      nI = Math.max(N >= 6 ? 1 : 0, Math.min(nI, floor(N * C.IND_PER16 / 16 + 0.5)));
      const cands: any = [];
      for (let i = 0; i < N; i++) {
        const ind = qs[i].ind;
        if (free(i) && ind && M.IND_FAM_K[ind.fam] != null) {
          let okA = false;
          for (const a of L.affixes) if (a.shape === 'industry' && a.fam === ind.fam && M.fillable(L, a, qs[i]) && !vetoed(ctx, a)) { okA = true; break; }
          if (okA) {
            const c = M.IND_FAM_K[ind.fam] * (1 - Math.min(1, (Number(ind.d) || 0) / C.IND_R)) + 0.05 * unit(ctx.seed, 'indclaim', idOf(i));
            cands.push({ i, c, fam: ind.fam });
          }
        }
      }
      const famUsed: any = {};
      hand('industry', cands, nI, (e: any) => { if (famUsed[e.fam]) return false; famUsed[e.fam] = true; return true; });
    }
    if ((P.count.whole || 0) > 0) {
      const cands: any = [];
      for (let i = 0; i < N; i++) if (free(i)) {
        let [c, a] = affixClaim(i, 'whole');
        // (NEXT_PHASE_BRIEF 60: a town granted its river spends it; a whole name that drops the river ranks lower there)
        if (ctx.rules !== 's53' && qs[i].river && a && !(a.needR || a.needT)) c = c - 0.5;
        if (c >= minOf(i, 'whole')) cands.push({ i, c });
      }
      hand('whole', cands, P.count.whole);
    }
    const nq = P.count.qualifier || 0;
    if (nq > 0) {
      const has: any = {};
      for (const a of L.affixes) if (a.shape === 'qualifier' && !a.joined && !a.mapDir) has[a.qkind] = true;
      const cands: any = [];
      for (let i = 0; i < N; i++) {
        if (free(i) && qs[i].river && qs[i].specs) {
          const w = ws[i];
          const k = (w.upper || 0) >= (w.lower || 0) ? 'upper' : 'lower';
          const v = w[k] || 0;
          if (v >= C.RIVER_QUAL_CUE && has[k]) cands.push({ i, c: v, k });
        }
      }
      const nr = hand('qualifier', cands, Math.min(nq, C.RIVER_QUAL_MAX), (e: any) => { P.qual[e.i] = { mode: 'river', kind: e.k }; return true; });
      let left = nq - nr;
      if (left > 0 && ctx.twins !== false) {
        const F = twinForms(L);
        const pairsL: any = [];
        const M2 = Math.min(N, C.TWIN_MAX_TOWNS);
        for (let i = 0; i < M2; i++) {
          const ti = list[i];
          if (!(free(i) && typeof ti.x === 'number')) continue;
          for (let j = i + 1; j < M2; j++) {
            const tj = list[j];
            if (!(free(j) && typeof tj.x === 'number')) continue;
            const d = Math.sqrt(Math.pow(ti.x - tj.x, 2) + Math.pow(ti.y - tj.y, 2));
            if (d > C.TWIN_MAX_M) continue;
            const ci = Number(ti.cap) || 0, cj = Number(tj.cap) || 0;
            let an = i, tw = j;
            if (cj > ci || (cj === ci && idOf(j) < idOf(i))) { an = j; tw = i; }
            if (list[tw].character) { const z = an; an = tw; tw = z; }
            if (list[tw].character) continue;
            const ta = list[an], tt = list[tw];
            let kind: any = null;
            const fa = ta.cue && typeof ta.cue.flow === 'number' ? ta.cue.flow : null;
            const ft = tt.cue && typeof tt.cue.flow === 'number' ? tt.cue.flow : null;
            const sameRiver = rsys[ta.id] != null && rsys[ta.id] === rsys[tt.id];
            if (sameRiver && fa != null && ft != null && Math.abs(fa - ft) >= C.TWIN_FLOW) kind = ft > fa ? 'upper' : 'lower';
            else if (typeof ta.alt === 'number' && typeof tt.alt === 'number' && Math.abs(ta.alt - tt.alt) >= C.TWIN_DZ) kind = tt.alt > ta.alt ? 'upper' : 'lower';
            if (kind && !F[kind]) kind = null;
            const ca = Number(ta.cap) || 0, ct = Number(tt.cap) || 0;
            if (kind == null && ct > 0 && ca >= C.TWIN_RATIO * ct && F.small) kind = 'small';
            const bonus = (kind === 'upper' || kind === 'lower') ? 0.3 : (kind === 'small' ? 0.2 : 0);
            if (kind == null) { const dr = dirFrom(tt.x - ta.x, tt.y - ta.y); if (F[dr]) kind = dr; }
            if (kind) pairsL.push({ an, tw, kind, c: 1 - d / C.TWIN_MAX_M + bonus });
          }
        }
        pairsL.sort((a?: any, c?: any) => a.c !== c.c ? c.c - a.c : (idOf(a.tw) !== idOf(c.tw) ? idOf(a.tw) - idOf(c.tw) : idOf(a.an) - idOf(c.an)));
        let nt = 0;
        for (const pr of pairsL) {
          if (nt >= left) break;
          if (free(pr.an) && free(pr.tw)) {
            taken[pr.an] = true; taken[pr.tw] = true;
            P.anchor[pr.an] = true;
            P.shape[pr.tw] = 'qualifier';
            P.twinOf[pr.tw] = { anchor: pr.an, kind: pr.kind };
            P.twins.push(pr.tw);
            nt++;
          }
        }
        P.used.qualifier = (P.used.qualifier || 0) + nt;
        left -= nt;
      }
      if (left > 0) {
        const sc: any = [];
        for (let i = 0; i < N; i++) {
          if (free(i)) {
            const c = affixClaim(i, 'qualifier', (a: any) => a.qkind === 'age' || a.qkind === 'other' || (a.joined && (a.qkind === 'upper' || a.qkind === 'lower')))[0];
            if (c >= minOf(i, 'qualifier')) sc.push({ i, c });
          }
        }
        hand('qualifier', sc, left, (e: any) => { P.qual[e.i] = { mode: 'site' }; return true; });
      }
    }
    if (ctx.rules === 's61') {
      // 2b. (NEXT_PHASE_BRIEF 61) evocative names, after the whole names and the twins
      let nE = floor(N * C.EVOC_SHARE + draw(ctx.seed, 11, 'evoc'));
      nE = Math.max(0, Math.min(nE, floor(N * C.EVOC_MAX)));
      const ec: any = [];
      for (let i = 0; i < N; i++) {
        if (!free(i)) continue;
        const opts: any = [];
        (qs[i].riverGrant === 'first' ? [] : L.affixes).forEach((a?: any, ai0?: any) => {
          if (a.shape === 'evoc' && !M.ruleOut(ctx, a) && M.gateOk(a, qs[i].wraw, qs[i].facts) && M.fillable(L, a, qs[i]) && !vetoed(ctx, a)) {
            let f = M.fit(a, xs[i])[0];
            if (a.rare) f = f + (list[i].character ? C.RARE_ON : -C.RARE_OFF);
            if (qs[i].river) f = f - C.EVOC_RIVER;
            f = f + 0.2 * unit(ctx.seed, 'evclaim', idOf(i), ai0 + 1);
            if (f >= C.EVOC_CLAIM) opts.push({ a, f });
          }
        });
        if (opts.length > 0) {
          opts.sort((p?: any, q?: any) => p.f !== q.f ? q.f - p.f : cmpStr(p.a.k || p.a.text, q.a.k || q.a.text));
          ec.push({ i, c: opts[0].f, opts });
        }
      }
      const planned: any = {};
      let multi = 0;
      hand('evoc', ec, nE, (e: any) => {
        for (const o of e.opts) {
          const k = o.a.k || o.a.text;
          if (!planned[k]) { planned[k] = true; if (M.tokens(o.a.r || o.a.text) >= 2) multi++; return true; }
        }
        return false;
      });
      if (multi > 0 && P.count.separate != null) P.count.separate = Math.max(0, P.count.separate - floor(multi * C.EVOC_SEP + 0.5));
    }
    if ((P.count.frame || 0) > 0) {
      const cands: any = [];
      for (let i = 0; i < N; i++) {
        if (free(i)) {
          const [c, a] = affixClaim(i, 'frame');
          if (c >= minOf(i, 'frame')) cands.push({ i, c, a, rv: a && (a.needR || a.needT) && qs[i].river ? (qs[i].river.s || qs[i].river.n) : null });
        }
      }
      const framed: any = {}, tpl: any = {};
      const cap = Math.max(1, floor(N / C.FRAME_PER));
      hand('frame', cands, P.count.frame, (e: any) => {
        if (e.rv && framed[e.rv]) return false;
        const k = e.a ? (e.a.k || e.a.text) : '-';
        if ((tpl[k] || 0) >= cap) return false;
        if (e.rv) framed[e.rv] = true;
        tpl[k] = (tpl[k] || 0) + 1;
        return true;
      });
    }
    if ((P.count.saint || 0) > 0) {
      const cands: any = [], any = (Q.saint || 0) >= C.SAINT_ANY;
      for (let i = 0; i < N; i++) if (free(i)) { const c = affixClaim(i, 'saint')[0]; if (c > -Infinity && (any || c >= minOf(i, 'saint'))) cands.push({ i, c }); }
      hand('saint', cands, P.count.saint);
    }
    if ((P.count.civic || 0) > 0) {
      const cands: any = [];
      for (let i = 0; i < N; i++) if (free(i) && !qs[i].noCivic) { const c = affixClaim(i, 'civic')[0]; if (c >= minOf(i, 'civic')) cands.push({ i, c }); }
      hand('civic', cands, P.count.civic);
    }
    const genClaim = (i?: any, f?: any) => {
      let best = -Infinity;
      L.gens.forEach((g?: any, gi0?: any) => {
        if (f(g) && !vetoed(ctx, g)) { const v = M.fit(g, xs[i])[0] + 0.05 * unit(ctx.seed, 'gclaim', idOf(i), gi0 + 1); if (v > best) best = v; }
      });
      return best;
    };
    if ((P.count.article || 0) > 0 && L.articles && typeof L.articles === 'object' && !L.script) {
      const cands: any = [];
      for (let i = 0; i < N; i++) if (free(i)) {
        const c = genClaim(i, (g: any) => g.gender != null && L.articles[g.gender] != null && (g.form === 'before' || g.form === 'pre'));
        if (c >= minOf(i, 'article')) cands.push({ i, c });
      }
      hand('article', cands, P.count.article);
    }
    if ((P.count.single || 0) > 0 && !L.script) {
      const cands: any = [];
      for (let i = 0; i < N; i++) if (free(i)) { const c = genClaim(i, (g: any) => g.flags.o === true); if (c >= minOf(i, 'single')) cands.push({ i, c }); }
      hand('single', cands, P.count.single);
    }
    const plain: any = [];
    for (let i = 0; i < N; i++) {
      if ((P.shape[i] == null || P.shape[i] === 'plain') && !list[i].keep && !list[i].character) {
        let topv = 0;
        for (const r of M.rankOf(ws[i])) if (M.ideaOf(r[0])) { topv = r[1]; break; }
        plain.push({ i, c: topv });
      }
    }
    plain.sort((a?: any, c?: any) => a.c !== c.c ? a.c - c.c : idOf(a.i) - idOf(c.i));
    // (NEXT_PHASE_BRIEF 61: the share of the towns left plain)
    let nPlainish = N;
    if (ctx.rules === 's61') for (let i = 0; i < N; i++) { const sh = P.shape[i]; if (sh === 'evoc' || sh === 'industry' || sh === 'character') nPlainish--; }
    const nQuiet = floor((ctx.rules === 's53' ? C.QUIET_SHARE_53 : C.QUIET_SHARE) * nPlainish + 0.5);
    for (let k = 0; k < Math.min(nQuiet, plain.length); k++) P.quiet[plain[k].i] = true;
    // 6. flavor towns (NEXT_PHASE_BRIEF 60): the best claims on a +n part, the coast and edge areas first
    P.flavor = {};
    if (ctx.rules !== 's53' && L.hasFlavor && N > 0) {
      let nF = floor(N * C.FLAVOR_SHARE + draw(ctx.seed, 9, 'flavor'));
      nF = Math.max(N >= 6 ? 1 : 0, Math.min(nF, floor(N * C.FLAVOR_MAX / 16 + 0.5)));
      const cands: any = [];
      for (let i = 0; i < N; i++) {
        if ((P.shape[i] == null || P.shape[i] === 'plain') && !P.quiet[i] && !P.anchor[i] && !list[i].keep && !list[i].character) {
          let best = -Infinity;
          for (const lst of [L.gens, L.specs]) for (const e of lst) {
            if (e.flags.n && !M.opaque(e) && !vetoed(ctx, e)) { const v = M.fit(e, xs[i])[0]; if (v > best) best = v; }
          }
          const q = qs[i];
          if (q.river) best = best + 0.3;
          if (q.dialect && q.dialect.role !== 'core') best = best + 0.3;
          best = best + 0.1 * draw(ctx.seed, idOf(i), 'flavorpick');
          if (best >= C.FLAVOR_MIN) cands.push({ i, c: best });
        }
      }
      cands.sort(byClaim);
      for (let k = 0; k < Math.min(nF, cands.length); k++) P.flavor[cands[k].i] = true;
    }
    return P;
  };
  M.shapeFields = function (st?: any): any {
    const sh = st && st.shapes;
    if (!sh) return [['quota', '-']];
    const text = (t: any) => { const parts: any = []; for (const k of M.SHAPES) if ((t[k] || 0) > 0) parts.push(k + ':' + t[k]); return parts.length ? parts.join(',') : '-'; };
    const ly = sh.layers || {};
    return [['quota', text(sh.quota)], ['used', text(sh.used)], ['frames', sh.used.frame || 0], ['whole', sh.used.whole || 0],
      ['twins', sh.twins], ['quiet', sh.quiet], ['towns', sh.towns], ['miss', sh.miss], ['left', sh.left],
      ['layers', 'old:' + (ly.old || 0) + ',mid:' + (ly.mid || 0) + ',late:' + (ly.late || 0)],
      ['desc', sh.desc || 0], ['opaque', sh.opaque || 0], ['flavor', sh.flavor || 0], ['multi', sh.multi || 0], ['rules', sh.rules || M.RULES],
      ['evoc', sh.evoc || 0], ['charCue', (sh.charCue || 0) + '/' + (sh.charN || 0)], ['indCue', sh.indCue || 0]];
  };

  M.assign = function (towns?: any, o?: any): any {
    o = o || {};
    const ctx = M.newCtx(o.lang, o.seed, o.real, o.used);
    if (!ctx) return [null, 'noGenerator'];
    ctx.climate = o.climate || undefined;
    ctx.cl = M.climateOf(ctx.L, o.climate);
    ctx.quota = ctx.cl.quota;
    ctx.twins = o.sat !== false;
    // (NEXT_PHASE_BRIEF 60: the descriptive rules unless o.rules = 's53'; the opaque and flavor caps)
    ctx.rules = o.rules || M.RULES;
    let words = ctx.cl.words;
    // (NEXT_PHASE_BRIEF 61: the s61 kinds' forms; under the older rules a secluded town is an ordinary character town,
    // deep forest / coastal towns none)
    ctx.charForms = ctx.rules === 's61' ? ctx.L.charForms61 : ctx.L.charForms;
    const list = towns.slice(0, C.MAX_TOWNS).map((t: any) => {
      const k = t.character;
      if (typeof k === 'string' && M.KINDS61[k] && ctx.rules !== 's61') return Object.assign({}, t, { character: k === 'secluded' });
      return t;
    });
    if (ctx.rules !== 's53') {
      ctx.quota = M.quota60(ctx.quota, o.lang);
      if (M.WORDS60[o.lang || ''] != null) words = Math.max(words || 0, M.WORDS60[o.lang]);
      if (ctx.rules === 's61' && M.WORDS61[o.lang || ''] != null) words = Math.max(words || 0, M.WORDS61[o.lang]);
      ctx.opaqueCap = Math.max(1, floor(list.length / C.OPAQUE_PER));
      ctx.flavorCap = Math.max(1, floor(list.length * C.FLAVOR_MAX / 16 + 0.5));
    }
    if (o.budget !== false) ctx.budget = M.NW.newBudget(M.CLS_OF_GEN[o.lang] || o.lang, list.length);
    let ws = list.map((t: any) => M.withCues(t.w, t.cue));
    const [layers, layerN] = M.layers(list, ws, o.year);
    const wcue = ws.slice();
    ctx.layers = layers;
    const rar = o.rarity !== false ? M.NW.rarity(ws) : {};
    ws = ws.map((w: any) => M.NW.applyRarity(w, rar));
    M.regions(ctx, list, ws);
    const riv: any = [], byComp: any = {}, compSys: any = {};
    for (const t of list) {
      const comp = t.cue && t.cue.river != null ? t.cue.river : null;
      if (comp != null) byComp[comp] = true; else if (t.river) riv.push(t);
    }
    const [rsys, rsystems] = M.riverSystems(riv);
    const comps = Object.keys(byComp).map(Number).sort((a?: any, c?: any) => a - c);
    for (const comp of comps) { rsystems.push({ ids: [], x: 0, y: 0, comp }); compSys[comp] = rsystems.length; }
    for (const t of list) {
      const comp = t.cue && t.cue.river != null ? t.cue.river : null;
      if (comp != null) { rsys[t.id] = compSys[comp]; rsystems[compSys[comp] - 1].ids.push(t.id); }
    }
    const lakeList: any = [], bigIds: any = [];
    for (const t of list) { if (t.cue && t.cue.lake) bigIds.push(t.id); else if (t.lake) lakeList.push(t); }
    const [lsys, lsystems] = M.lakeSystems(lakeList);
    if (bigIds.length > 0) { lsystems.push({ ids: bigIds, x: 0, y: 0, big: true }); for (const id of bigIds) lsys[id] = lsystems.length; }
    const idx: any = {};
    list.forEach((t?: any, i?: any) => { idx[t.id] = i; });
    const areaOf = (ids: any) => {
      let n = 0, cx = 0, cy = 0;
      for (const id of ids) { const t = idx[id] != null ? list[idx[id]] : null; if (t && typeof t.x === 'number') { n++; cx += t.x; cy += t.y; } }
      if (n === 0) return null;
      const d = M.dialectAt(ctx, cx / n, cy / n);
      return d ? d.name : null;
    };
    const rnames: any = [], lnames: any = [];
    for (let k = 1; k <= rsystems.length; k++) rnames[k] = M.riverName(ctx, k);
    const lhigh: any = {};
    for (const t of list) { const k = lsys[t.id]; if (k && t.w && t.w.tarn) lhigh[k] = true; }
    for (let k = 1; k <= lsystems.length; k++) lnames[k] = M.lakeName(ctx, k, lhigh[k] === true, areaOf(lsystems[k - 1].ids));
    const mountIds: any = [], bayIds: any = [];
    ws.forEach((w?: any, i?: any) => {
      if ((w.peak || 0) > 0 || (w.summit || 0) > 0 || (w.range || 0) > 0 || (w.divide || 0) > 0) mountIds.push(list[i].id);
      if ((w.bigbay || 0) > 0) bayIds.push(list[i].id);
    });
    const mount = mountIds.length > 0 ? M.featName(ctx, 'mount', areaOf(mountIds)) : null;
    const bay = bayIds.length > 0 ? M.featName(ctx, 'bay') : null;
    const featWord = (x: any) => { if (x && typeof x.s === 'string') ctx.featWords[lowerAll(x.s)] = true; };
    for (let k = 1; k <= rsystems.length; k++) featWord(rnames[k]);
    for (let k = 1; k <= lsystems.length; k++) featWord(lnames[k]);
    featWord(mount); featWord(bay);
    if (ctx.budget) {
      M.attachExtra(ctx.budget, o.lang, ctx.featWords, ctx.rules === 's61');
      M.NW.setTowns(ctx.budget, list.map((t: any) => [t.x, t.y]));
    }
    for (const t of list) if (t.keep && typeof t.name === 'string') { M.take(ctx, t.name); M.NW.add(ctx.budget, t.name, t.x, t.y); }
    const memOf = (ids: any) => { const mem: any = []; for (const id of ids) if (idx[id] != null && !list[idx[id]].keep) mem.push(idx[id]); return mem; };
    const feats: any = [];
    for (let k = 1; k <= rsystems.length; k++) if (rnames[k]) feats.push({ kind: 'river', members: memOf(rsystems[k - 1].ids) });
    for (let k = 1; k <= lsystems.length; k++) if (lnames[k]) feats.push({ kind: 'lake', members: memOf(lsystems[k - 1].ids) });
    if (mount) feats.push({ kind: 'mount', members: memOf(mountIds) });
    const bayCue: any = [];
    for (const t of list) if (t.cue && t.cue.bigbay) bayCue.push(t.id);
    if (bay) feats.push({ kind: 'bay', members: memOf(bayCue) });
    const [grants, leftClaims, leftList] = M.featureGrants(ctx, list, ws, feats);
    const glayer: any = {};
    const G0 = ctx.cl.group;
    if (G0 && list.length > 0) {
      const ang = draw(ctx.seed, 7, 'glayer') * 2 * Math.PI;
      const ca = Math.cos(ang), sa = Math.sin(ang);
      const pr: any = [];
      list.forEach((t?: any, i?: any) => { if (typeof t.x === 'number' && typeof t.y === 'number') pr.push({ i, v: t.x * ca + t.y * sa, id: Number(t.id) || 0 }); });
      pr.sort((a?: any, c?: any) => a.v !== c.v ? c.v - a.v : a.id - c.id);
      const share = ctx.rules !== 's53' ? Math.min(G0.share, C.FLAVOR_SHARE + 0.03) : G0.share;
      for (let k = 0; k < Math.min(pr.length, floor(list.length * share + 0.5)); k++) glayer[pr[k].i] = G0.grp;
    }
    const qs = list.map((t?: any, i?: any) => {
      const cue = t.cue || {}, g = grants[i] || {};
      const rv = rsys[t.id] ? rnames[rsys[t.id]] : null;
      const lk = lsys[t.id] ? lnames[lsys[t.id]] : null;
      const q: any = { id: t.id, x: t.x, y: t.y, w: ws[i], character: t.character, river: g.river ? rv : null,
        riverGrant: (g.river && rv) ? g.river : null, lake: g.lake ? lk : null,
        mount: g.mount ? mount : null, bay: (g.bay && cue.bigbay && bay) || null, dir: cue.dir, ldir: cue.ldir,
        layer: layers[i], saints: ctx.cl.saints, glayer: glayer[i] };
      // (NEXT_PHASE_BRIEF 61: the evocative gates' reading, the survey's facts, the industry near)
      if (ctx.rules === 's61') {
        q.wraw = wcue[i]; q.facts = (t.facts && typeof t.facts === 'object') ? t.facts : null;
        if (t.ind && typeof t.ind.fam === 'string' && typeof t.ind.d === 'number' && t.ind.d <= C.IND_R) q.ind = { fam: t.ind.fam, d: t.ind.d };
      }
      q.noCivic = layers[i] !== 'late' || (wcue[i].confluence || 0) >= C.CIVIC_CONFLUENCE || (wcue[i].twin || 0) >= C.CIVIC_CONFLUENCE;
      if (typeof t.character === 'string' && t.character !== '') q.charKind = t.character;
      if (q.river) {
        const e = M.riverEntry(ctx, rv);
        if (!ctx.L.script) e.boost = g.river === 'first' ? C.FEAT_FIRST : C.FEAT_BONUS;
        if (e) q.specs = [e];
      }
      let d = M.dialectAt(ctx, t.x, t.y);
      if (d && d.other && draw(ctx.seed, Number(t.id) || 0, 'borrow') < C.BORROW_P) d = { name: d.other.name, role: d.other.role, w: d.other.w, hybrid: false, borrowed: true };
      q.dialect = d;
      return q;
    });
    ctx.frameCap = Math.max(1, floor(list.length / C.FRAME_PER));
    const plan = o.shapes === false ? { shape: {}, count: {}, used: {}, quiet: {}, qual: {}, twinOf: {}, twins: [], anchor: {} }
      : M.planShapes(ctx, list, ws, qs, rsys);
    ctx.plan = plan;
    const target = words;
    if (target != null && !isNaN(target)) {
      let reserved = 0;
      for (let i = 0; i < list.length; i++) if (plan.shape[i] && M.AFFIX_SHAPES[plan.shape[i]]) reserved++;
      ctx.wordAllow = floor(list.length * (target - 1)) - reserved; ctx.wordExtra = 0; ctx.wordN = 0; ctx.wordTowns = list.length;
    }
    // (NEXT_PHASE_BRIEF 61: the evocative and industry towns right after the character towns)
    const order = list.map((t?: any, i?: any) => { const rk = M.rankOf(ws[i]); return { i, ch: t.character ? 0 : ((plan.shape[i] === 'evoc' || plan.shape[i] === 'industry') ? 1 : 2), top: (rk[0] && rk[0][1]) || 0, id: Number(t.id) || 0 }; });
    order.sort((a?: any, c?: any) => a.ch !== c.ch ? a.ch - c.ch : (a.top !== c.top ? c.top - a.top : a.id - c.id));
    const res: any = [];
    const st: any = { named: 0, none: 0, rivers: 0, lakes: 0, kept: 0 };
    for (let k = 1; k <= rsystems.length; k++) if (rnames[k]) st.rivers++;
    for (let k = 1; k <= lsystems.length; k++) if (lnames[k]) st.lakes++;
    const waterOf = (t: any) => [rsys[t.id] ? rnames[rsys[t.id]] : null, lsys[t.id] ? lnames[lsys[t.id]] : null];
    const nameOne = (i?: any, shape?: any) => {
      const t = list[i], q = qs[i];
      q.shape = o.shapes !== false ? (shape || plan.shape[i] || 'plain') : null;
      q.quiet = plan.quiet[i] === true;
      q.flavor = plan.flavor != null && plan.flavor[i] === true;
      const ql = plan.qual[i];
      q.qualMode = ql ? ql.mode : null; q.qualKind = ql ? ql.kind : null;
      const [nm, info] = M.nameTown(ctx, q);
      const [rv, lk] = waterOf(t);
      res[i] = { id: t.id, old: t.name, new: nm || t.name, info, river: rv ? rv.n : null, lake: lk ? lk.n : null };
      if (nm) st.named++; else st.none++;
    };
    for (const od of order) {
      const t = list[od.i];
      if (t.keep) {
        const [rv, lk] = waterOf(t);
        res[od.i] = { id: t.id, old: t.name, new: t.name, info: null, river: rv ? rv.n : null, lake: lk ? lk.n : null, why: 'keep' };
        st.kept++;
      } else if (plan.twinOf[od.i] == null) nameOne(od.i);
    }
    let nTwins = 0;
    for (const i of plan.twins) {
      const tw = plan.twinOf[i];
      const r = res[tw.anchor];
      let done = false;
      const inf = r && r.info;
      if (inf && inf.affix == null && inf.base && (inf.shape === 'plain' || inf.shape === 'separate' || inf.shape === 'personal') &&
        !(ctx.opaqueCap != null && (inf.opaque || inf.flavor))) {
        const q = qs[i];
        const forms = twinForms(ctx.L)[tw.kind] || [];
        const ranked = forms.map((a?: any, k0?: any) => {
          const k = k0 + 1;
          let f = -(k - 1) + 1.6 * draw(ctx.seed, (Number(list[i].id) || 0) * 7 + k, 'twin');
          if (a.rare) f = f - C.RARE_OFF;
          return { a, f, k };
        });
        ranked.sort((a?: any, c?: any) => a.f !== c.f ? c.f - a.f : a.k - c.k);
        const skip = ctx.budget ? M.NW.budgetKeys(ctx.budget, r.new) : null;
        const uses = featureUses(ctx, q, { s: { e: inf.sE } }, null);
        for (const e of ranked) {
          const full = fillAffix(ctx.L, e.a, inf.base, q);
          if (!full) continue;
          const nm = ctx.L.script === 'kanji' ? full + b('市') : full;
          const over = M.tokens(nm) > 2 && M.wordsOver(ctx, M.tokens(nm) - 2);
          if (!over && M.chars(full) <= C.MAX_FULL && M.free(ctx, nm) && M.tokens(nm) <= C.MAX_TOKENS && featureOk(ctx, uses) &&
            !M.climateWord(ctx, nm) && M.NW.allow(ctx.budget, nm, list[i].x, list[i].y, skip)) {
            M.take(ctx, nm);
            featureTake(ctx, uses);
            M.NW.add(ctx.budget, nm, list[i].x, list[i].y, skip);
            ctx.shapeUse.qualifier = (ctx.shapeUse.qualifier || 0) + 1;
            M.countWords(ctx, nm, true);
            ctx.affUse[e.a.k || e.a.text] = (ctx.affUse[e.a.k || e.a.text] || 0) + 1;
            const [rv, lk] = waterOf(list[i]);
            res[i] = { id: list[i].id, old: list[i].name, new: nm, river: rv ? rv.n : null, lake: lk ? lk.n : null,
              info: { spec: inf.spec, gen: inf.gen, affix: e.a.k || e.a.text, whole: false, feature: 'twin', specTag: inf.specTag, genTag: inf.genTag,
                score: 0, dialect: inf.dialect, base: inf.base, sE: inf.sE, gE: inf.gE, aE: e.a, shape: 'qualifier', quiet: false,
                twin: list[tw.anchor].id, twinKind: tw.kind, hybrid: inf.hybrid, layer: q.layer } };
            st.named++; nTwins++; done = true;
            break;
          }
        }
      }
      if (!done) nameOne(i, 'plain');
    }
    const waters: any = [];
    list.forEach((t?: any, i?: any) => {
      const r = res[i];
      const add = (n?: any, k?: any) => { if (waters.length < C.WATER_CAP && n && typeof t.x === 'number') waters.push({ n, x: floor(t.x + 0.5), y: floor(t.y + 0.5), k }); };
      if (r && r.river) add(r.river, 'r');
      if (r && r.lake) add(r.lake, 'l');
    });
    st.waters = waters;
    const used: any = {}; let quiet = 0;
    for (const r of res) if (r && r.info && r.info.shape) { used[r.info.shape] = (used[r.info.shape] || 0) + 1; if (r.info.quiet) quiet++; }
    // (NEXT_PHASE_BRIEF 60: names with a readable site word, opaque, flavor and multi-word names)
    let nDesc = 0, nOpq = 0, nFlv = 0, nMulti = 0, nNamed = 0;
    // (NEXT_PHASE_BRIEF 61: evocative names, character towns of a kind that carry it, industry cue names)
    let nEvoc = 0, nChar = 0, nCharCue = 0, nInd = 0;
    res.forEach((r?: any, i?: any) => {
      if (qs[i] && qs[i].charKind && (ctx.charForms || {})[qs[i].charKind]) { nChar++; if (r && r.info && r.info.shape === 'character') nCharCue++; }
      if (r && r.info && r.info.shape === 'evoc') nEvoc++;
      if (r && r.info && r.info.shape === 'industry') nInd++;
    });
    res.forEach((r?: any, i?: any) => {
      if (!r || !r.info) return;
      r.info.site = M.siteWord(r.info, wcue[i]);
      nNamed++;
      if (r.info.site) nDesc++;
      if (r.info.opaque) nOpq++;
      if (r.info.flavor) nFlv++;
      if (M.tokens(r.new) >= 2) nMulti++;
    });
    st.shapes = { quota: plan.count, used, twins: nTwins, quiet, towns: list.length, miss: ctx.shapeMiss || 0, left: leftClaims, layers: layerN,
      desc: nDesc, opaque: nOpq, flavor: nFlv, multi: nMulti, named: nNamed, rules: ctx.rules, evoc: nEvoc, charN: nChar, charCue: nCharCue, indCue: nInd };
    st.layers = layers; st.leftList = leftList;
    st.qs = qs;  // (lab only: the towns' naming inputs, for the shape A/B test)
    st.plan = plan; st.satellite = 0;
    st.ctx = ctx; st.budget = ctx.budget; st.misfit = ctx.misfit; st.climate = ctx.climate; st.rarity = rar; st.mount = mount; st.bay = bay; st.weights = ws;
    return [res, st];
  };
  // the river's stem as a part (assign): kanji / romaji take the stem entry itself
  M.riverEntry = function (ctx?: any, rv?: any): any {
    if (ctx.L.script) return rv.e;
    const e = newEntry(rv.s);
    e.kind = 'stem';
    parseTags([rv.s, 'river', 'mouth:.8', 'ford:.8', 'bridge:.8', 'confluence:.6', 'bend:.6', 'brook:.5'], 2, e);
    e.river = true;
    return e;
  };
  // ---------------------------------------------------------------- ot_namewords (the word budget, rarity)
  M.NW = (function (): any {
    const N = DATA.nw || { WORDS: {}, WORDS_OF: {}, SOFT: {}, consts: {}, RARE_EXEMPT: {} };
    const K = N.consts;
    const NUP: any = { 'à': 'À', 'á': 'Á', 'â': 'Â', 'ä': 'Ä', 'å': 'Å', 'æ': 'Æ', 'ç': 'Ç', 'è': 'È', 'é': 'É', 'ê': 'Ê', 'í': 'Í',
      'ñ': 'Ñ', 'ó': 'Ó', 'ô': 'Ô', 'ö': 'Ö', 'ø': 'Ø', 'ú': 'Ú', 'ü': 'Ü', 'ō': 'Ō', 'ū': 'Ū', 'î': 'Î', 'ë': 'Ë', 'ï': 'Ï' };
    const NDOWN: any = {};
    for (const k in NUP) NDOWN[b(NUP[k])] = b(k);
    const WORDS: any = {};
    for (const lex in N.WORDS) WORDS[lex] = N.WORDS[lex].map((e: any) => [e[0], e[1], b(e[2])]);
    const W: any = {};
    W.lower = (s: any) => String(s == null ? '' : s).replace(/[A-Z]/g, (ch: any) => ch.toLowerCase()).replace(/[\xc3\xc5][\x80-\xbf]/g, (ch: any) => NDOWN[ch] || ch);
    const words = (low: any) => (low.match(/[^ \t\-'.,/]+/g) || []).slice(0, K.MAX_WORDS);
    const hits = (how?: any, text?: any, raw?: any, ws?: any) => {
      if (how === 'h') return raw.indexOf(text) >= 0;
      const n = text.length;
      for (const w of ws) {
        if (how === 'w') { if (w === text) return true; }
        else if (how === 'e') { if (w.length >= n + 2 && w.slice(-n) === text) return true; }
        else if (how === 's') { if (w.length >= n + 2 && w.slice(0, n) === text) return true; }
      }
      return false;
    };
    W.keys = function (name?: any, cls?: any): any {
      const lex = WORDS[N.WORDS_OF[cls || ''] || ''];
      if (!lex || typeof name !== 'string' || name === '') return [];
      const low = W.lower(name), ws = words(low), seen: any = {}, out: any = [];
      for (const e of lex) if (!seen[e[0]] && hits(e[1], e[2], e[1] === 'h' ? name : low, ws)) { seen[e[0]] = true; out.push(e[0]); }
      return out.sort();
    };
    W.fold = function (w?: any): any {
      if (typeof w !== 'string' || w.length < 5 || w.slice(-1) !== 's' || w.slice(-2) === 'ss') return w;
      if (w.slice(-3) === 'xes' || w.slice(-4) === 'ches' || w.slice(-4) === 'shes') return w.slice(0, -2);
      return w.slice(0, -1);
    };
    W.STOP = {};
    for (const w of Object.keys(N.STOP || {})) W.STOP[b(w)] = true;
    W.newBudget = function (cls?: any, nTowns?: any, o?: any): any {
      o = o || {};
      const n = Math.max(1, Number(nTowns) || 1);
      return { cls, cap: Math.max(1, Math.ceil(n / (o.perTowns || K.PER_TOWNS))), rootCap: Math.max(1, Math.ceil(n / K.ROOT_PER)),
        near: o.near || K.NEAR_M, used: {}, pts: {}, held: {}, entries: 0, heldN: 0, extra: null, tpos: null, hood: {}, hoodN: 0 };
    };
    W.setTowns = function (B?: any, list?: any): any {
      if (B == null) return;
      const t: any = [];
      (list || []).forEach((p?: any, i0?: any) => {
        if (i0 + 1 > K.MAX_ENTRIES) return;
        if (typeof p[0] === 'number' && typeof p[1] === 'number') t.push([p[0], p[1]]);
      });
      B.tpos = t.length > K.HOOD ? t : null; B.hood = {}; B.hoodN = 0;
    };
    // (Lua's string.format("%.0f:%.0f"): round half to even, as C's printf)
    const f0 = (v: any) => { const r = Math.round(v); return (Math.abs(v % 1) === 0.5 && r % 2 !== 0) ? String(r - 1) : String(r); };
    W.hoodR2 = function (B?: any, x?: any, y?: any): any {
      if (B == null || B.tpos == null || typeof x !== 'number' || typeof y !== 'number') return 0;
      const key = f0(x) + ':' + f0(y);
      let c = B.hood[key];
      if (c != null) return c;
      const d: any = [];
      for (const p of B.tpos) { const q = Math.pow(p[0] - x, 2) + Math.pow(p[1] - y, 2); if (q > 1) d.push(q); }
      d.sort((a?: any, c2?: any) => a - c2);
      c = d[Math.min(K.HOOD, d.length) - 1];
      if (c == null) c = 0;
      if (B.hoodN >= K.HOOD_CACHE) { B.hood = {}; B.hoodN = 0; }
      B.hood[key] = c; B.hoodN++;
      return c;
    };
    const skipSet = (skip: any) => { const s: any = {}; for (const k of (skip || [])) s[k] = true; return s; };
    W.budgetKeys = function (B?: any, name?: any): any {
      const k = W.keys(name, B.cls);
      if (B.extra) {
        let ex: any = null;
        try { ex = B.extra(name); } catch (e: any) { ex = null; }
        if (Array.isArray(ex)) ex.forEach((w?: any, i0?: any) => { if (i0 + 1 <= K.MAX_WORDS) k.push(w); });
      }
      return k;
    };
    const capOf = (B?: any, k?: any) => {
      const c = k.slice(0, 1);
      if (c === '=') return 1;
      if (k.slice(0, 2) === '%!') return 1;
      if (c === '^') return B.rootCap || B.cap;
      return B.cap * (N.SOFT[k] ? K.SOFT_K : 1);
    };
    const near2 = (B?: any, k?: any, x?: any, y?: any) => {
      const soft = N.SOFT[k] ? K.SOFT_K : 1;
      const n = B.near / soft;
      let d2 = n * n;
      if (soft === 1) { const h = W.hoodR2(B, x, y); if (h > d2) d2 = h; }
      return d2;
    };
    W.check = function (B?: any, name?: any, x?: any, y?: any, skip?: any, keys?: any): any {
      if (B == null) return [true];
      const sk = skipSet(skip);
      for (const k of (keys || W.budgetKeys(B, name))) {
        if (sk[k]) continue;
        if ((B.used[k] || 0) >= capOf(B, k)) return [false, k, 'cap'];
        if (typeof x === 'number' && typeof y === 'number' && B.pts[k]) {
          const d2 = near2(B, k, x, y);
          for (const p of B.pts[k]) if (p[0] != null && Math.pow(p[0] - x, 2) + Math.pow(p[1] - y, 2) <= d2) return [false, k, 'near'];
        }
      }
      return [true];
    };
    W.blockedKeys = function (B?: any, x?: any, y?: any, skip?: any): any {
      const out: any = {};
      if (B == null) return out;
      const sk = skipSet(skip);
      for (const k in B.used) {
        const n = B.used[k];
        if (sk[k] || !(n > 0)) continue;
        if (n >= capOf(B, k)) out[k] = true;
        else if (typeof x === 'number' && typeof y === 'number') {
          const d2 = near2(B, k, x, y);
          for (const p of (B.pts[k] || [])) if (p[0] != null && Math.pow(p[0] - x, 2) + Math.pow(p[1] - y, 2) <= d2) { out[k] = true; break; }
        }
      }
      return out;
    };
    W.hold = function (B?: any, key?: any): any { if (B == null || key == null) return; B.held[key] = (B.held[key] || 0) + 1; B.heldN++; };
    W.allow = function (B?: any, name?: any, x?: any, y?: any, skip?: any, keys?: any): any { const [okB, k] = W.check(B, name, x, y, skip, keys); if (!okB) W.hold(B, k); return okB; };
    W.add = function (B?: any, name?: any, x?: any, y?: any, skip?: any, keys?: any): any {
      if (B == null || B.entries >= K.MAX_ENTRIES) return;
      B.entries++;
      const sk = skipSet(skip);
      for (const k of (keys || W.budgetKeys(B, name))) {
        if (sk[k]) continue;
        B.used[k] = (B.used[k] || 0) + 1;
        (B.pts[k] = B.pts[k] || []).push([typeof x === 'number' ? x : null, typeof y === 'number' ? y : null]);
      }
    };
    W.remove = function (B?: any, name?: any, x?: any, y?: any): any {
      if (B == null) return;
      for (const k of W.budgetKeys(B, name)) {
        if ((B.used[k] || 0) > 0) B.used[k]--;
        const pts = B.pts[k] || [];
        for (let i = pts.length - 1; i >= 0; i--) if (pts[i][0] === x && pts[i][1] === y) { pts.splice(i, 1); break; }
      }
    };
    W.rarity = function (maps?: any): any {
      const ex = N.RARE_EXEMPT || {};
      const n = (maps || []).length, out: any = {};
      if (n < K.RARE_MIN_TOWNS) return out;
      const count: any = {};
      for (const w of maps) for (const t in (w || {})) { const v = w[t]; if (typeof v === 'number' && v >= K.RARE_MIN_W && !ex[t]) count[t] = (count[t] || 0) + 1; }
      for (const t in count) {
        const share = count[t] / n;
        if (share > K.RARE_SHARE) {
          const f = 1 - (share - K.RARE_SHARE) / (1 - K.RARE_SHARE) * (1 - K.RARE_MIN);
          out[t] = Math.max(K.RARE_MIN, Math.min(1, f));
        }
      }
      return out;
    };
    W.applyRarity = function (w?: any, f?: any): any { const out: any = {}; for (const t in (w || {})) out[t] = (f && f[t] != null) ? w[t] * f[t] : w[t]; return out; };
    W.usedText = function (B?: any): any {
      if (!B) return '-';
      const ks = Object.keys(B.used).filter((k: any) => B.used[k] > 0).sort();
      return ks.length ? ks.map((k: any) => k + ':' + B.used[k]).join(',') : '-';
    };
    return W;
  })();
  M.fillAffix = fillAffix;
  return M;
}

export { create, rng, b, u };
