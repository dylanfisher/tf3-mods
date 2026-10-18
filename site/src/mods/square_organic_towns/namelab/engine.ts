// Name lab engine: the five generator ideas over the TS port of ot_placename (gen.ts), driven by the lab state.
// Ported from the old lab page (plans/square_organic_towns/names/lab.js); no React here.
import { b, create, rng, u } from "./gen.ts";
import { NAMEIDEAS, type Ideas } from "./ideas.ts";
import type { LabState, NameData } from "./types.ts";

export type ModeId = "morph" | "remix" | "desc" | "feat" | "old";

export const MODES: { id: ModeId; name: string; desc: string }[] = [
  { id: "morph", name: "Morpheme", desc: "The mod's generator (ot_placename): a stem and a generic picked by how well their tags fit the site, dialect, affix." },
  { id: "remix", name: "Real-name remix", desc: "A character Markov chain trained on the game's own town list for the language, optionally starting with a fitting stem or ending with a fitting generic." },
  { id: "desc", name: "Descriptive", desc: "Terrain words only: plain terrain / color words and the terrain generics, no personal names, no affix (\"Ashwater\", \"Fellside\")." },
  { id: "feat", name: "Feature + settlement", desc: "The river or lake's name with a settlement word (\"Avonbury\", \"Lahnheim\"); a stream name when the site has no water." },
  { id: "old", name: "Old forms", desc: "Old spellings of the morpheme names, and the inventory's Celtic / Norse forms (Aber-, Pen-, -by, -thwaite) pushed forward." },
];
export const MODE: Record<string, (typeof MODES)[number]> = Object.fromEntries(MODES.map((m) => [m.id, m]));

const TOWNISH: Record<string, 1> = { any: 1, market: 1, church: 1, big: 1, small: 1, character: 1, district: 1, works: 1, old: 1, new: 1 };
const SETTLE: Record<string, 1> = { any: 1, plain: 1, field: 1, meadow: 1, market: 1, church: 1, old: 1, big: 1, small: 1 };

export function tagGroups(D: NameData): [string, string[]][] {
  return [
    ["Rivers", ["river", "mouth", "ford", "bridge", "bend", "confluence", "spring", "brook"]],
    ["Lakes", ["lake", "mere", "pool", "tarn"]],
    ["Coast", ["coast", "sandy", "rocky", "cliff", "bay", "headland", "spit", "island"]],
    ["Hills", ["hill", "hilltop", "slope", "ridge", "pass", "foot", "mountain", "rock"]],
    ["Valleys", ["valley", "vale", "gorge", "combe"]],
    ["Wet ground, heath", ["marsh", "fen", "moor", "heath"]],
    ["Forest", ["forest", "edge", "clearing"]],
    ["Trees", D.pn.SPECIES],
    ["Open land", ["plain", "field", "meadow"]],
    ["Town", ["market", "church", "big", "small", "district", "works", "old", "new"]],
  ];
}

export const LANG_NAMES: Record<string, string> = {
  en: "English (England)", usa: "American English", de: "German", fr: "French", it: "Italian", es: "Spanish",
  pt: "Portuguese", nl: "Dutch", sv: "Swedish", nb: "Norwegian", ja: "Japanese (kanji)", ja_r: "Japanese (romaji)",
};
export const CLIMATES = [
  { value: "temperate", label: "Temperate" },
  { value: "tropical", label: "Tropical" },
  { value: "dry", label: "Dry" },
  { value: "subarctic", label: "Subarctic" },
];
export const baseLang = (l: string) => (l === "ja_r" ? "ja" : l);
export const f2 = (v: unknown) => (v == null || isNaN(v as number) ? "-" : (+(v as number)).toFixed(2));

/** One generated name (or a failure) as the result views show it. */
export interface NameResult {
  mode: ModeId;
  name: string | null;
  fail?: unknown;
  parts?: string[];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  info?: any;
  river?: string | null;
  lake?: string | null;
  // old forms
  modern?: string;
  applied?: string[];
  how?: string;
  // remix
  stem?: { text: string; f: number; bt: string } | null;
  gen?: { text: string; f: number; bt: string } | null;
  order?: number;
  minO?: number;
  trainN?: number;
  tries?: number;
}

function mulberry(a: number) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const hasRiver = (w: Record<string, number>) => w.river != null;
const hasLake = (w: Record<string, number>) => w.lake != null || w.pool != null || w.mere != null || w.tarn != null;
const partsOf = (info: { spec?: string; gen?: string; affix?: string } | null | undefined) =>
  !info ? [] : ([u(info.spec), u(info.gen), info.affix ? u(info.affix) : null].filter(Boolean) as string[]);

/* eslint-disable @typescript-eslint/no-explicit-any */
/** The generator engine for one data set. `rebuild(S)` after edits to the constants, specificity or lists. */
export class Lab {
  readonly D: NameData;
  readonly M0: any;
  M: any;
  private realCache: Record<string, Record<string, true>> = {};
  private chainCache: Record<string, any> = {};

  constructor(D: NameData) {
    this.D = D;
    this.M0 = create(D);
    this.M = this.M0;
  }

  rebuild(S: Pick<LabState, "consts" | "spec" | "edits">) {
    this.M = create(this.D, { consts: S.consts, spec: S.spec, edits: S.edits });
  }

  realSet(lang: string) {
    if (!this.realCache[lang]) {
      const r: Record<string, true> = {};
      for (const n of (this.D.towns[lang] || {}).names || []) r[this.M0.lowerAll(b(n))] = true;
      this.realCache[lang] = r;
    }
    return this.realCache[lang];
  }

  ideas(S: LabState, lang: string): Ideas {
    const bl = baseLang(lang);
    return Object.assign({ adj: "", old: "", oldGroups: "" }, NAMEIDEAS[bl] || {}, (S.ideas || {})[bl] || {});
  }

  /** The site's tag weights (>= 0.2 counts), plus the character town's tags. */
  siteW(S: LabState) {
    const w: Record<string, number> = {};
    for (const k in S.site) if (S.site[k] >= 0.2) w[k] = S.site[k];
    if (S.character) { w.character = 1; w.church = Math.max(w.church || 0, 0.4); }
    return w;
  }

  ranked(w: Record<string, number>): [string, number][] {
    return this.M.ranked(w);
  }

  private dialectObj(S: LabState, L: any) {
    if (S.dialect === "auto" || S.dialect === "none") return null;
    // (NEXT_PHASE_BRIEF 53: a dialect area's weights, its own group first)
    return this.M.areaObj(L, b(S.dialect));
  }

  // A run of n towns with the same site. hook(ctx, q, i, L) -> result.
  private runTowns(S: LabState, n: number, opts: { shared?: boolean; hook: (ctx: any, q: any, i: number, L: any) => NameResult | null }) {
    const M = this.M;
    const L = M.lang(S.lang);
    const w = this.siteW(S);
    // (the map's climate, ot_climate: its site tags in, the tags it never takes out, as siteTags does)
    const clim = S.climate || "temperate";
    const site = (M.CL.SITE || {})[clim] || {};
    for (const k in site) if ((w[k] || 0) < site[k]) w[k] = site[k];
    for (const k in w) if (M.vetoTag(clim, k)) delete w[k];
    const out: NameResult[] = [];
    const shared = opts.shared != null ? opts.shared : S.shared;
    let ctx: any = null;
    // shared: one map, every town in one context; alone: each town on its own map (seed + i)
    const fresh = (i: number) => {
      const c = M.newCtx(S.lang, shared ? S.seed : S.seed + i - 1, this.realSet(S.lang));
      c.climate = S.climate || "temperate";
      // (NEXT_PHASE_BRIEF 60: the rules; descriptive runs cap opaque and flavor parts as a map of n towns does, every
      // 8th town a flavor town)
      c.rules = S.rules || "s61";
      // (NEXT_PHASE_BRIEF 61: the s61 kinds' forms)
      c.charForms = c.rules === "s61" ? c.L.charForms61 : c.L.charForms;
      if (c.rules !== "s53") { c.opaqueCap = Math.max(1, Math.floor(n / 16)); c.flavorCap = Math.max(1, Math.floor(n * 3 / 16 + 0.5)); }
      if (S.dialect === "auto") {
        const towns = [];
        for (let j = 1; j <= n; j++) towns.push({ x: ((j - 1) % 7) * 6000, y: Math.floor((j - 1) / 7) * 6000 });
        M.regions(c, towns);
      }
      // (the map's word budget, ot_namewords: a generic word at most once per 8 towns of the run; the towns stand 6 km
      // apart, so the 5 km neighbor rule doesn't bite here)
      if (shared && S.budget !== false) c.budget = M.NW.newBudget(M.CLS_OF_GEN[S.lang] || S.lang, n);
      return c;
    };
    const rivers: Record<number, any> = {}, lakes: Record<number, any> = {};
    for (let i = 1; i <= n; i++) {
      if (!ctx || !shared) ctx = fresh(i);
      const id = 1000 + i;
      const q: any = { id, x: ((i - 1) % 7) * 6000, y: Math.floor((i - 1) / 7) * 6000, w, character: S.character };
      // the map survey's facts for the cue tags of the site: the compass side, the side of the big lake, the map's
      // mountain and bay (named once per context)
      let bd: string | null = null, bv = 0;
      for (const d of ["north", "south", "east", "west"]) if ((w[d] || 0) > bv) { bd = d; bv = w[d]; }
      if (bd) q.dir = bd;
      if ((w.biglake || 0) > 0) q.ldir = bd || "west";
      if ((w.peak || 0) > 0 || (w.summit || 0) > 0 || (w.range || 0) > 0 || (w.divide || 0) > 0) {
        if (ctx.labMount === undefined) ctx.labMount = M.featName(ctx, "mount");
        q.mount = ctx.labMount;
      }
      if ((w.bigbay || 0) > 0) {
        if (ctx.labBay === undefined) ctx.labBay = M.featName(ctx, "bay");
        q.bay = ctx.labBay;
      }
      const dia = this.dialectObj(S, L);
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
      if (S.affixP < 1 && rng.unit(S.seed, "labAffix", id) >= S.affixP) q.noAffix = true;
      if ((S.rules || "s61") !== "s53" && i % 8 === 0) q.flavor = true;
      // (NEXT_PHASE_BRIEF 61: every 5th town tries an evocative name on the site's reading, as the map plan's ~20 %; a
      // site whose reading holds no gate goes plain)
      if ((S.rules || "s61") === "s61" && i % 5 === 0) { q.shape = "evoc"; q.wraw = w; }
      const r = opts.hook(ctx, q, i, L);
      if (r) out.push(r);
    }
    return out;
  }

  private morphResult(mode: ModeId, ctx: any, q: any): NameResult {
    const [nm, info] = this.M.nameTown(ctx, q);
    if (!nm) return { mode, name: null, fail: info };
    return { mode, name: u(nm), parts: partsOf(info), info, river: q.river ? u(q.river.n) : null, lake: q.lake ? u(q.lake.n) : null };
  }

  private genMorph(S: LabState, n: number) {
    return this.runTowns(S, n, { hook: (ctx, q) => this.morphResult("morph", ctx, q) });
  }

  private descLists(S: LabState, L: any) {
    const M = this.M;
    const specs = L.specs.filter((e: any) => !e.flags.p && !e.flags.c && e.main && !TOWNISH[e.main] && (L.script || e.kind !== "phrase"));
    for (const toks of M.lines(b(this.ideas(S, S.lang).adj))) specs.push(M.parseSpec(toks, false));
    const gens = L.gens.filter((e: any) => !e.flags.p && !e.flags.c && !e.flags.t && e.main && !TOWNISH[e.main]);
    return [specs, gens];
  }
  private genDesc(S: LabState, n: number) {
    return this.runTowns(S, n, {
      hook: (ctx, q, _i, L) => {
        const [specs, gens] = this.descLists(S, L);
        q.specList = specs; q.gens = gens; q.noAffix = true; q.specs = null; q.dialect = q.dialect || null;
        if (!q.dialect) q.dialect = { name: b("none"), w: {} };
        return this.morphResult("desc", ctx, q);
      },
    });
  }

  private featLists(S: LabState, ctx: any, L: any, w: Record<string, number>) {
    const M = this.M;
    const feats: any[] = [];
    const water = hasRiver(w) || hasLake(w);
    if (hasLake(w)) {
      for (const stem of L.data.lakes ? L.data.lakes.split("|") : []) {
        const e = M.newEntry(stem); e.kind = "stem"; M.parseTags([stem, "lake", "mere:.6", "pool:.5"], 2, e); e.feature = "lake"; feats.push(e);
      }
    }
    if (hasRiver(w) || !water || feats.length === 0) {
      const c2 = M.newCtx(S.lang, S.seed + 7, this.realSet(S.lang));
      for (let k = 1; k <= 12; k++) {
        const rv = M.riverName(c2, k);
        if (!rv) break;
        // the river's stem as join allows it (prefixes: "Villeloue") and as a plain stem ("Vila Mondego")
        for (const plain of [false, true]) {
          const e = M.riverEntry(ctx, rv);
          if (!water) { e.tl = [["brook", 1], ["river", 0.6]]; M.parseTags([], 2, e); }
          if (plain && !L.script) e.river = false;
          e.feature = water ? "river" : "stream";
          if (!plain || !L.script) feats.push(e);
        }
      }
    }
    const gens = L.gens.filter((e: any) => !e.flags.p && !e.flags.c && (SETTLE[e.main] || e.tl.some((p: any) => p[0] === "any" && p[1] >= 0.3)));
    return [feats, gens];
  }
  private genFeat(S: LabState, n: number) {
    return this.runTowns(S, n, {
      hook: (ctx, q, _i, L) => {
        const [feats, gens] = this.featLists(S, ctx, L, q.w);
        q.specList = feats; q.gens = gens; q.noAffix = true; q.specs = null;
        return this.morphResult("feat", ctx, q);
      },
    });
  }

  oldRules(S: LabState, lang: string): [RegExp, string, string][] {
    const out: [RegExp, string, string][] = [];
    for (const line of this.ideas(S, lang).old.split("\n")) {
      const t = line.trim();
      if (!t || t[0] === "#") continue;
      if (t.indexOf("=>") < 0) continue;
      const pat = line.slice(0, line.indexOf("=>")).trim(), rep = line.slice(line.indexOf("=>") + 2).replace(/^ /, "");
      try { out.push([new RegExp(pat, "g"), rep, pat]); } catch { /* bad regex: skipped */ }
    }
    return out;
  }
  private genOld(S: LabState, n: number) {
    const rules = S.opt.spelling ? this.oldRules(S, S.lang) : [];
    const groups = this.ideas(S, S.lang).oldGroups.split(/\s+/).filter(Boolean);
    return this.runTowns(S, n, {
      hook: (ctx, q, _i, L) => {
        const pref = rng.unit(S.seed, "labOld", q.id) < S.opt.oldShare;
        let how = "spelling";
        if (pref && groups.length) {
          const g = L.gens.filter((e: any) => e.grp && groups.indexOf(u(e.grp)) >= 0);
          if (g.length) { q.gens = g; q.dialect = { name: b("old"), w: {} }; how = "old " + groups.join(" / ") + " forms"; }
        }
        const r = this.morphResult("old", ctx, q);
        if (!r.name) return r;
        // (each word on its own: "$" is a word's end, "Strathburn-in-the-Forest" -> "Strathburne-in-the-Forest")
        const applied: string[] = [];
        const nm = r.name.split(/([ \-]+)/).map((wd, wi) => {
          if (wi % 2 === 1 || wd === "") return wd;
          for (const [re, rep, pat] of rules) {
            re.lastIndex = 0;
            const nn = wd.replace(re, rep);
            if (nn !== wd) { if (applied.indexOf(pat + " => " + rep) < 0) applied.push(pat + " => " + rep); wd = nn; }
          }
          return wd;
        }).join("");
        r.modern = r.name; r.name = nm; r.applied = applied; r.how = how;
        return r;
      },
    });
  }

  // remix: back-off character Markov chain
  trainingSet(lang: string) {
    const t = this.D.towns[lang] || {};
    return { n: (t.names || []).length, sources: t.sources || [] };
  }
  private chain(lang: string, order: number, single: boolean) {
    const key = lang + "|" + order + "|" + single;
    if (this.chainCache[key]) return this.chainCache[key];
    // (kanji: without the 市 / 町 / 村 the generator adds itself)
    let names = ((this.D.towns[lang] || {}).names || []).map((n) => (lang === "ja" ? n.replace(/[市町村]$/, "") : n)).filter(Boolean);
    if (single) names = names.filter((n) => !/[ \-]/.test(n));
    const tbl: Record<string, Record<string, number>>[] = [];
    for (let o = 1; o <= order; o++) tbl[o] = {};
    for (const n of names) {
      const s = Array.from("\u0002".repeat(order) + n + "\u0003");
      for (let i = order; i < s.length; i++) {
        for (let o = 1; o <= order; o++) {
          const ctxS = s.slice(i - o, i).join("");
          const m = tbl[o][ctxS] || (tbl[o][ctxS] = {});
          m[s[i]] = (m[s[i]] || 0) + 1;
        }
      }
    }
    return (this.chainCache[key] = { tbl, order, n: names.length, names });
  }
  private nextChar(C: any, hist: string[], rnd: () => number): [string, number] {
    for (let o = C.order; o >= 1; o--) {
      const ctxS = hist.slice(-o).join("");
      const m = C.tbl[o][ctxS];
      if (m) {
        let tot = 0; for (const k in m) tot += m[k];
        let x = rnd() * tot;
        for (const k in m) { x -= m[k]; if (x < 0) return [k, o]; }
      }
    }
    return ["\u0003", 0];
  }
  private genRemix(S: LabState, n: number) {
    const M = this.M;
    const lang = S.lang, L = M.lang(lang), C = this.chain(lang, S.opt.order, S.opt.singleWords);
    const real = this.realSet(lang), used: Record<string, true> = {};
    const w = this.siteW(S), x = M.expandSite(w);
    const t = { id: 1, character: S.character, dialect: this.dialectObj(S, L) };
    const ctx = M.newCtx(lang, S.seed, real);
    const stems = M.rankParts(ctx, L.specs.filter((e: any) => e.kind === "stem" && !e.flags.c), x, t, "s", {}, 0).slice(0, 12);
    const gens = M.rankParts(ctx, L.gens.filter((e: any) => e.form === "suf" || e.form === "ja"), x, t, "g", {}, 0).slice(0, 12);
    const out: NameResult[] = [];
    if (C.n === 0) return out;
    for (let i = 1; i <= n; i++) {
      const rnd = mulberry(rng.hash(S.seed, "remix", i));
      let got: NameResult | null = null;
      for (let tries = 0; tries < 300 && !got; tries++) {
        const roll = rnd();
        let hist = Array.from("\u0002".repeat(C.order)), pre = "", suf: string | null = null, how = "chain", stem: any = null, gen: any = null;
        if (roll < S.opt.bias / 2 && stems.length) {
          stem = stems[Math.floor(rnd() * Math.min(6, stems.length))];
          pre = L.script === "romaji" ? M.capFirst(stem.e.r) : L.script ? stem.e.k : stem.e.text;
          pre = u(pre); hist = hist.concat(Array.from(pre)); how = "stem + chain";
        } else if (roll < S.opt.bias && gens.length) {
          gen = gens[Math.floor(rnd() * Math.min(6, gens.length))];
          suf = u(L.script === "romaji" ? gen.e.r : L.script ? gen.e.k : gen.e.text); how = "chain + generic";
        }
        let s = pre, minO = 9;
        const maxLen = suf ? 7 : 14;
        while (Array.from(s).length < maxLen + pre.length) {
          const [c, o] = this.nextChar(C, hist, rnd);
          if (c === "\u0003") break;
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
        if (L.script === "kanji" && !s.endsWith("市")) s += "市";
        got = {
          mode: "remix", name: s, parts: [pre || null, suf || null].filter(Boolean) as string[], how,
          stem: stem ? { text: u(stem.e.k || stem.e.text), f: stem.f, bt: stem.bt } : null,
          gen: gen ? { text: u(gen.e.k || gen.e.text), f: gen.f, bt: gen.bt } : null,
          order: C.order, minO, trainN: C.n, tries,
        };
      }
      if (got) out.push(got);
    }
    return out;
  }

  generate(S: LabState, mode: ModeId, n: number): NameResult[] {
    try {
      switch (mode) {
        case "morph": return this.genMorph(S, n);
        case "remix": return this.genRemix(S, n);
        case "desc": return this.genDesc(S, n);
        case "feat": return this.genFeat(S, n);
        case "old": return this.genOld(S, n);
      }
    } catch (e) {
      console.error(e);
      return [{ mode, name: null, fail: String((e as Error)?.message || e) }];
    }
  }

  /** The exported map's towns through the lab's engine (current edits): one context, character towns and the most
   *  distinctive sites first (as assign), the log's dialect, river and lake names. */
  mapLabNames(S: LabState): Record<string, { name: string; parts: string[] } | null> {
    const D = this.D, M = this.M, mp = D.map;
    if (!mp) return {};
    const lang = mp.summary && mp.summary.gen && D.lang[baseLang(mp.summary.gen)] ? mp.summary.gen : S.lang;
    const L = M.lang(lang);
    if (!L) return {};
    const ctx = M.newCtx(lang, S.seed, this.realSet(lang));
    const order = mp.towns.map((t, i) => ({ t, i, top: t.tags[0] ? t.tags[0][1] : 0 }));
    order.sort((a, c) => (a.t.character === c.t.character ? 0 : a.t.character ? -1 : 1) || c.top - a.top || +a.t.id - +c.t.id);
    const out: Record<string, { name: string; parts: string[] } | null> = {};
    for (const { t } of order) {
      const w: Record<string, number> = {};
      for (const [k, v] of t.tags) w[k] = Math.min(1, v / (M.SPEC[k] || 1));
      const q: any = { id: +t.id, w, character: t.character };
      const d = t.dialect && t.dialect !== "-" ? M.areaObj(L, b(t.dialect)) : null;
      if (d) q.dialect = d;
      if (t.river) { q.river = { n: b(t.river), s: b(t.river) }; q.specs = [M.riverEntry(ctx, q.river)]; }
      if (t.lake) q.lake = { n: b(t.lake), s: b(t.lake) };
      const [nm, info] = M.nameTown(ctx, q);
      out[t.id] = nm ? { name: u(nm), parts: partsOf(info) } : null;
    }
    return out;
  }

  // ---- morpheme lists
  origText(lang: string, kind: ListKind): string {
    return this.D.lang[baseLang(lang)][kind] || "";
  }
  curText(S: LabState, lang: string, kind: ListKind): string {
    const e = (S.edits[baseLang(lang)] || {})[kind];
    return e != null ? e : this.origText(lang, kind);
  }
  /** The list's lines with their parse and fit to the current site. */
  listRows(S: LabState, kind: ListKind) {
    const M = this.M, lang = S.lang;
    const lines = this.curText(S, lang, kind).split("\n").filter((l) => l.trim() !== "");
    const orig = new Set(this.origText(lang, kind).split("\n").map((l) => l.trim()).filter(Boolean));
    const L = M.lang(lang), x = M.expandSite(this.siteW(S));
    const parse = kind === "spec" ? M.parseSpec : kind === "gen" ? M.parseGen : M.parseAffix;
    return lines.map((line, i) => {
      const toks = b(line).match(/[^ \t\r]+/g) || [];
      const e = toks.length ? parse(toks, !!L.script) : null;
      const [fit, bt] = e ? M.fit(e, x) : [0, null];
      return { i, line, e, fit: fit as number, bt, changed: !orig.has(line.trim()) };
    });
  }
}

export type ListKind = "spec" | "gen" | "affix";

/** Remove a list edit when it equals the original text. Returns the new edits object. */
export function withListText(lab: Lab, S: LabState, lang: string, kind: ListKind, txt: string): LabState["edits"] {
  const bl = baseLang(lang);
  const edits = { ...S.edits, [bl]: { ...(S.edits[bl] || {}) } };
  if (txt === lab.origText(lang, kind)) delete edits[bl][kind];
  else edits[bl][kind] = txt;
  if (!Object.keys(edits[bl]).length) delete edits[bl];
  return edits;
}

export { u };
