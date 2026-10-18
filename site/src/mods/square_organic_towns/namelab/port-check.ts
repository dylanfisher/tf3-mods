// The port check (shared by the Name lab's Port check tab and plans/square_organic_towns/names/check_port.mjs):
// re-runs Lua's golden maps (data.json `golden`) with the TS port (gen.ts) and compares every name and part, and
// compares the TS parse of every inventory line with Lua's (`parsed`). Erasable TypeScript only (Node runs it).

export interface PortLang {
  lang: string;
  n: number;
  ok: number;
  bad: { id: unknown; lua: unknown; js: unknown; luaScore?: number; jsScore?: number }[];
}
export interface PortResult {
  langs: PortLang[];
  ok: number;
  n: number;
  parse: { lang: string; kind: string; i: number; js: string; lua: string }[];
}

export function run(D: any, NG: any): PortResult {
  const M = NG.create(D);
  const { b, u } = NG;
  const out: PortResult = { langs: [], ok: 0, n: 0, parse: [] };
  // (the plain runs, then the climate runs of NEXT_PHASE_BRIEF 49: golden.byClimate)
  // (NEXT_PHASE_BRIEF 60: the same maps with the s53 rules, golden53)
  const runs: any = [[null, D.golden.byLang, null]];
  for (const c in (D.golden.byClimate || {})) runs.push([c, D.golden.byClimate[c], null]);
  // (NEXT_PHASE_BRIEF 61: the §60 rules too, golden60)
  if (D.golden60) {
    runs.push([null, D.golden60.byLang, 's60']);
    for (const c in (D.golden60.byClimate || {})) runs.push([c, D.golden60.byClimate[c], 's60']);
  }
  if (D.golden53) {
    runs.push([null, D.golden53.byLang, 's53']);
    for (const c in (D.golden53.byClimate || {})) runs.push([c, D.golden53.byClimate[c], 's53']);
  }
  for (const [climate, byLang, rules] of runs) for (const lang of D.pn.LANGS) {
    const g = byLang[lang];
    if (!g) continue;
    const real: any = {};
    for (const n of ((D.towns[lang] || {}).names || [])) real[M.lowerAll(b(n))] = true;
    const towns = D.golden.towns.map((t: any) => {
      const w0 = Object.assign({}, t.w);
      if (climate) {
        const site = (D.climate.SITE || {})[climate] || {};
        for (const k in site) if ((w0[k] || 0) < site[k]) w0[k] = site[k];
        for (const k in w0) if (M.vetoTag(climate, k)) delete w0[k];
      }
      const w: any = {};
      for (const k in w0) if (w0[k] >= 0.2) w[k] = w0[k];
      return { id: t.id, name: b(t.name), x: t.x, y: t.y, w, ranked: M.ranked(w), character: t.character, cap: t.cap,
        river: t.river, axis: t.axis == null ? undefined : t.axis, lake: t.lake, cue: t.cue || undefined, keep: t.keep || undefined,
        alt: t.alt == null ? undefined : t.alt, ind: t.ind || undefined, facts: t.facts || undefined };
    });
    const [res] = M.assign(towns, { lang, seed: D.golden.seed, real, climate: climate || undefined, year: D.golden.year,
      rules: rules || undefined });
    const L: PortLang = { lang: (climate ? lang + '/' + climate.slice(0, 3) : lang) + (rules ? '/' + rules : ''), n: 0, ok: 0, bad: [] };
    g.rows.forEach((row?: any, i?: any) => {
      const r = res[i], inf = r && r.info && typeof r.info === 'object' ? r.info : {};
      const js: any = { new: u(r.new), spec: u(inf.spec), gen: u(inf.gen), affix: u(inf.affix) || undefined, shape: inf.shape || undefined };
      const lu: any = { new: row.new, spec: row.spec, gen: row.gen, affix: row.affix || undefined, shape: row.shape || undefined };
      const same = js.new === lu.new && js.spec === lu.spec && js.gen === lu.gen && js.affix === lu.affix && js.shape === lu.shape &&
        (row.score == null || Math.abs((inf.score || 0) - row.score) < 1e-9);
      L.n++; if (same) L.ok++; else L.bad.push({ id: row.id, lua: lu, js, luaScore: row.score, jsScore: inf.score });
    });
    out.langs.push(L); out.n += L.n; out.ok += L.ok;
    // parser (once per language)
    if (climate || rules) continue;
    const Lx = M.lang(lang), P = D.parsed[lang];
    for (const kind of ['spec', 'gen', 'affix']) {
      const js = kind === 'spec' ? Lx.specs : (kind === 'gen' ? Lx.gens : Lx.affixes);
      (P[kind] || []).forEach((pe?: any, i?: any) => {
        const e = js[i];
        const a = e ? JSON.stringify([u(e.text), e.kind || e.form || null, e.tl, Object.keys(e.flags).sort(), u(e.grp) || null, !!e.rare, u(e.cls) || null]) : 'missing';
        const c = JSON.stringify([pe.text, pe.kind || pe.form || null, pe.tl || [], pe.flags || [], pe.grp || null, !!pe.rare, pe.cls || null]);
        if (a !== c) out.parse.push({ lang, kind, i, js: a, lua: c });
      });
    }
  }
  return out;
}
