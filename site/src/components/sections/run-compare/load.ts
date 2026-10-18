// Build time: read every <source.dir>/<page>/data.json of a run-compare section and turn one into the viewer's
// model. Images come from the media build (src/lib/media.ts); a missing one is just left out. A missing source.dir, a
// data.json that does not parse, has an unknown version or no runs fails the build with the file named.
import fs from "node:fs";
import path from "node:path";
import { fmt, plural } from "@/lib/format";
import { getMedia } from "@/lib/media";
import { repoPath } from "@/lib/repo";
import { runColor } from "@/lib/run-colors";
import { slugify } from "@/lib/slug";
import type { SectionProps } from "../types";
import { DEFAULT_RUN, DEFAULT_UNIT } from "./source";
import {
  RAW_VERSIONS, type CompareEntry, type CompareFacts, type CompareModel, type EntryCounts, type Img, type ModelUnit,
  type RawCompare, type RawExtra, type RawRun, type RawUnit, type RunCompareSource, type UnitNames,
} from "./types";

type Props = SectionProps<RunCompareSource>;

function img(mod: string, src: string): Img | undefined {
  const e = getMedia(mod, src);
  return e && { thumb: e.thumb.url, full: e.full.url, w: e.thumb.width, h: e.thumb.height, fw: e.full.width };
}

const lastYear = (r: RawRun): number | null => {
  const y = r.years;
  if (typeof y === "number") return y;
  if (Array.isArray(y) && y.length) {
    const n = Number(y.at(-1)?.year);
    return Number.isFinite(n) ? Math.trunc(n) : null;
  }
  return null;
};

// version 2 data names the units "towns" (Organic Towns' first builder)
const unitsOf = (d: RawCompare): RawUnit[] => d.units ?? d.towns ?? [];
const extrasOf = (d: RawCompare): Record<string, RawExtra[]> => d.extraUnits ?? d.extraTowns ?? {};

/** Version 2 key notes were HTML with <b> and <code> only: the same as inline markup, other tags dropped. */
const legacyNote = (html: string): string =>
  html
    .replace(/<b>([\s\S]*?)<\/b>/g, "**$1**")
    .replace(/<code>([\s\S]*?)<\/code>/g, "`$1`")
    .replace(/<[^>]*>/g, "")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&");

function readData(file: string, rel: string): RawCompare {
  let raw: RawCompare;
  try {
    raw = JSON.parse(fs.readFileSync(file, "utf8")) as RawCompare;
  } catch (e) {
    throw new Error(`${rel}: ${(e as Error).message}`);
  }
  if (!(RAW_VERSIONS as readonly number[]).includes(raw.version))
    throw new Error(`${rel}: data version ${raw.version ?? "(none)"} is not one of ${RAW_VERSIONS.join(", ")} (rebuild it with its builder)`);
  if (!Array.isArray(raw.runs) || !raw.runs.length) throw new Error(`${rel}: no runs`);
  return raw;
}

function counts(runs: CompareEntry["runs"], units: number, extra: number, unit: UnitNames, run: UnitNames): EntryCounts {
  const years = runs.map((r) => r.years).filter((y): y is number => y != null);
  return {
    runs: { value: runs.length, label: plural(runs.length, run.one, run.many) },
    units: { value: units, label: plural(units, unit.one, unit.many), extra },
    years: years.length ? Math.max(...years) : null,
  };
}

const cache = new Map<string, CompareEntry[]>();

/** Every comparison of the section, newest first (by `built`, then folder name). */
export function loadEntries({ mod, section }: Props): CompareEntry[] {
  const key = `${mod.id}/${section.slug}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const src = section.source;
  const unit = src.unit ?? DEFAULT_UNIT;
  const runName = src.runName ?? DEFAULT_RUN;
  const root = repoPath(src.dir);
  if (!fs.existsSync(root)) throw new Error(`${key}: run-compare source.dir '${src.dir}' does not exist`);
  const dirs = fs.readdirSync(root, { withFileTypes: true })
    .filter((d) => d.isDirectory() && fs.existsSync(path.join(root, d.name, "data.json")))
    .map((d) => d.name);
  const out: CompareEntry[] = [];
  for (const dir of dirs) {
    const raw = readData(path.join(root, dir, "data.json"), `${src.dir}/${dir}/data.json`);
    const runs = raw.runs;
    const h = raw.header ?? {};
    const units = unitsOf(raw);
    const extras = extrasOf(raw);
    // list thumbnail: the first unit shot of the first run that has one
    let thumb: Img | undefined;
    for (const r of runs) {
      const u = units.find((t) => t.m[r.id]?.shot);
      if (u) {
        thumb = img(mod.id, `${src.dir}/${dir}/${u.m[r.id]!.shot}`);
        if (thumb) break;
      }
    }
    const single = !!raw.single || runs.length === 1;
    const facts: CompareFacts = {
      seed: raw.seed ?? "",
      single,
      runs,
      units: units.length,
      extra: Object.fromEntries(runs.map((r) => [r.id, extras[r.id]?.length ?? 0])),
      pairing: raw.pairing ?? (units.every((u) => Object.values(u.samePos ?? {}).every(Boolean)) ? "id" : "id-or-position"),
      summary: raw.summary ?? {},
      notes: raw.notes ?? {},
    };
    const entryRuns = runs.map((r) => ({
      id: r.id,
      label: r.label,
      kind: r.kind ?? "",
      session: r.session ?? "",
      load: r.load == null ? "" : String(r.load),
      years: lastYear(r),
      card: src.runCard?.(r) ?? [],
    }));
    const extra = Object.values(extras).reduce((n, l) => n + (l?.length ?? 0), 0);
    const notes = raw.notes?.keyNotes ?? [];
    out.push({
      slug: slugify(dir),
      dir,
      title: h.title || dir,
      h1: h.h1 || h.title || dir,
      description: src.describe?.(facts) ?? `${entryRuns.length} ${plural(entryRuns.length, runName.one, runName.many)} · ${units.length} ${plural(units.length, unit.one, unit.many)}`,
      seed: raw.seed ?? "",
      date: (raw.built ?? "").slice(0, 10),
      built: raw.built ?? "",
      single,
      runs: entryRuns,
      units: units.length,
      extra,
      counts: counts(entryRuns, units.length, extra, unit, runName),
      thumb,
      keyNotes: [...(raw.version >= 3 ? notes : notes.map(legacyNote)), ...(src.autoNotes?.(facts) ?? [])],
      raw,
    });
  }
  out.sort((a, b) => b.built.localeCompare(a.built) || b.dir.localeCompare(a.dir));
  cache.set(key, out);
  return out;
}

/** Page-header facts of a comparison. */
export function entryStats(e: CompareEntry) {
  const c = e.counts;
  return [
    c.runs,
    { label: c.units.label, value: c.units.extra ? `${c.units.value} +${c.units.extra}` : c.units.value },
    ...(c.years != null ? [{ label: "years", value: c.years }] : []),
    ...(e.seed ? [{ label: "seed", value: e.seed }] : []),
    ...(e.built ? [{ label: "built", value: e.built }] : []),
  ];
}

/** The viewer's model of one comparison. */
export function buildModel({ mod, section }: Props, e: CompareEntry): CompareModel {
  const src = section.source;
  const d = e.raw;
  const base = `${src.dir}/${e.dir}`;
  const runs = d.runs.map((r, i) => ({ id: r.id, label: r.label, color: runColor(i) }));
  const S = d.summary ?? {};

  const summaryRows = src.summaryRows.map((row) => {
    const cells: CompareModel["summary"]["rows"][number]["cells"] = {};
    const digits = row.digits ?? 0;
    const sc = row.scale ?? 1;
    for (const r of runs) {
      const s = S[row.key]?.[r.id];
      if (row.mode === "sum") {
        const v = s?.sum ?? null;
        cells[r.id] = { text: v == null ? "-" : fmt(v / sc, digits), value: v };
      } else {
        const q = s?.q;
        cells[r.id] = q
          ? { text: fmt(q[1] / sc, digits), range: `[${fmt(q[0] / sc, digits)}-${fmt(q[2] / sc, digits)}]`, value: q[1] }
          : { text: "-", value: null };
      }
    }
    return { label: row.label, cells };
  });

  const units: ModelUnit[] = unitsOf(d).map((t) => {
    const per: ModelUnit["runs"] = {};
    for (const r of runs) {
      const m = t.m[r.id];
      if (!m) continue;
      const x = t.x?.[r.id] ?? undefined;
      per[r.id] = {
        name: m.name ?? "-",
        img: m.shot ? img(mod.id, `${base}/${m.shot}`) : undefined,
        notes: x && src.unitNotes ? src.unitNotes(x, m).join(" · ") : "",
        facts: src.gallery?.facts(m, x),
        flags: src.gallery?.flags?.(m, x),
      };
    }
    const rows = src.unitRows.map((row) => {
      const cells: Record<string, string> = {};
      for (const r of runs) { const m = t.m[r.id]; cells[r.id] = m ? row.cell(m) : "-"; }
      const rk = row.ratioKey;
      const ratio = rk ? Object.fromEntries(runs.map((r) => { const v = t.m[r.id]?.[rk]; return [r.id, typeof v === "number" ? v : null]; })) : null;
      return { label: row.label, cells, ratio };
    });
    const ids = [...new Set(Object.values(t.ids ?? {}).filter((v) => v != null).map(String))].join(" / ");
    return { nn: t.nn, ids, category: t.category ?? "unrated", verdict: t.verdict ?? "", runs: per, rows };
  });

  const cats = src.categories ?? {};
  const usedCats = new Set(units.map((u) => u.category));
  const categories = Object.entries(cats).filter(([k]) => usedCats.has(k)).map(([value, c]) => ({ value, ...c }));

  const ex = src.extras;
  const extras = extrasOf(d);
  const extraRows = ex
    ? runs.flatMap((r) => (extras[r.id] ?? []).map((x) => ({
        run: r.id,
        name: x.name,
        cells: ex.columns.map((c) => (typeof x[c.key] === "number" ? fmt(x[c.key], c.digits ?? 0) : String(x[c.key] ?? "-"))),
        img: x.shot ? img(mod.id, `${base}/${x.shot}`) : undefined,
        shotName: x.shot ? x.shot.split("/").pop() : undefined,
        facts: ex.facts?.(x),
      })))
    : [];

  return {
    order: src.order ?? "viewer-first",
    key: `${mod.id}/${section.slug}/${e.dir}`,
    sectionKey: `${mod.id}/${section.slug}`,
    single: e.single,
    unit: src.unit ?? DEFAULT_UNIT,
    runName: src.runName ?? DEFAULT_RUN,
    runs,
    summary: {
      hint: e.single
        ? src.summaryHint?.single ?? "Median [quartiles] or sum over the units."
        : src.summaryHint?.multi ?? "Median [quartiles] or sum over the paired units. The last column is the ratio of the runs picked as A and B (A / B).",
      rows: summaryRows,
    },
    runRows: (d.runRows ?? []).map((row) => ({ label: String(row[0] ?? ""), cells: row.slice(1).map((v) => String(v ?? "")) })),
    units,
    categories,
    verdictLabel: src.verdictLabel ?? "Verdict:",
    gallery: e.single && src.gallery ? { hint: src.gallery.hint } : undefined,
    extras: ex ? { title: ex.title, description: ex.description, columns: ex.columns.map((c) => c.label), rows: extraRows, tag: ex.tag } : undefined,
  };
}
