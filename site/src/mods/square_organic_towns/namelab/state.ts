// Name lab state: defaults, persistence in the site's storage scheme (src/lib/storage.ts; the lab works without
// storage), link parameters (#mode=remix|all&lang=de&tab=lists&preset=island&seed=7) and the settings export.
import { migrateStore, readStore, removeStore, writeStore } from "@/lib/storage";
import { baseLang, MODE } from "./engine.ts";
import type { LabState, NameData, RatedName } from "./types.ts";

const KEY = "square_organic_towns/name-lab/state";
/** the key before the site's scheme (and of the old names/ page): read once into KEY, then dropped */
const LEGACY_KEY = "ot-name-lab-v1";

export function defaults(D: NameData): LabState {
  return {
    v: 1, lang: "en", climate: "temperate", rules: "s61", mode: "morph", view: "grid", seed: 1, dialect: "auto", affixP: 1,
    character: false, shared: true, budget: true, preset: "lakeside", site: { ...(D.presets.lakeside || {}) },
    consts: {}, spec: {}, edits: {}, ideas: {},
    opt: { order: 3, bias: 0.5, singleWords: true, oldShare: 0.4, spelling: true, count: 50 },
    ratings: {}, pinned: {}, notes: "", tab: "map", listKind: "spec", listFilter: "", listSort: "fit",
  };
}

export function loadState(D: NameData): LabState {
  const d = defaults(D);
  let S = d;
  migrateStore(KEY, LEGACY_KEY);
  const o = readStore(KEY) as Partial<LabState> | undefined;
  if (o && o.v === 1) S = { ...d, ...o, opt: { ...d.opt, ...(o.opt || {}) } };
  try {
    const h = new URLSearchParams(location.hash.slice(1));
    const mode = h.get("mode");
    if (mode === "all") S.view = "all";
    else if (mode) { S.view = "grid"; S.mode = mode as LabState["mode"]; }
    if (h.get("lang")) S.lang = h.get("lang")!;
    if (h.get("tab")) S.tab = h.get("tab")!;
    if (h.get("seed")) S.seed = +h.get("seed")! || 1;
    const p = h.get("preset");
    if (p && D.presets[p]) { S.preset = p; S.site = { ...D.presets[p] }; }
  } catch { /* ignore */ }
  if (!D.lang[baseLang(S.lang)]) S.lang = "en";
  if (!MODE[S.mode]) S.mode = "morph";
  return S;
}

export function saveState(S: LabState) {
  writeStore(KEY, S);
}

export function clearState() {
  removeStore(KEY);
}

/** Everything the visitor changed, as the JSON the export downloads ("implement this"). */
export function buildExport(D: NameData, S: LabState, site: Record<string, number>) {
  const C0 = D.pn.consts;
  const consts: Record<string, { mod: number; lab: number }> = {}, spec: Record<string, { mod: number; lab: number }> = {};
  for (const k in S.consts) if (S.consts[k] !== C0[k]) consts[k] = { mod: C0[k], lab: S.consts[k] };
  for (const k in S.spec) if (S.spec[k] !== D.pn.SPEC[k]) spec[k] = { mod: D.pn.SPEC[k], lab: S.spec[k] };
  const listEdits: Record<string, Record<string, { added: string[]; removed: string[] }>> = {};
  for (const l in S.edits) {
    for (const kind of Object.keys(S.edits[l]) as ("spec" | "gen" | "affix")[]) {
      const a = new Set((D.lang[l][kind] || "").split("\n").map((s) => s.trim()).filter(Boolean));
      const bb = new Set((S.edits[l][kind] || "").split("\n").map((s) => s.trim()).filter(Boolean));
      listEdits[l] = listEdits[l] || {};
      listEdits[l][kind] = { added: [...bb].filter((x) => !a.has(x)), removed: [...a].filter((x) => !bb.has(x)) };
    }
  }
  const strip = (r: RatedName) => ({
    name: r.name, mode: r.mode, lang: r.lang, parts: r.parts, site: r.site, character: r.character,
    ...(r.r ? { rating: r.r > 0 ? "up" : "down" } : {}),
  });
  return {
    kind: "organic-towns-name-lab", version: 1, exported: new Date().toISOString(), data: { built: D.built, src: D.src },
    request: "Implement these name-generation settings in ot_placename / ot_placename_lang.",
    settings: {
      lang: S.lang, climate: S.climate, rules: S.rules || "s61", mode: S.mode, view: S.view, seed: S.seed, dialect: S.dialect, affixProbability: S.affixP,
      character: S.character, wordBudget: S.budget, sharedMap: S.shared, preset: S.preset, site,
    },
    modeOptions: S.opt, constants: consts, specificity: spec, listEdits, ideaEdits: { ...S.ideas },
    ratings: Object.values(S.ratings).map(strip), pinned: Object.values(S.pinned).map(strip), notes: S.notes,
  };
}
