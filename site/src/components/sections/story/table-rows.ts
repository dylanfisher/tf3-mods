// Build time: the rows of a story "deltas" block read from a data-explorer data file (tools/site_table.py, version 1),
// grouped by columns (DeltaTable in ./types.ts). Fails loudly on a missing file, version or column.
import type { RawTable } from "../data-explorer/types";
import { readJson } from "@/lib/repo";
import type { DeltaTable } from "./types";

const cache = new Map<string, RawTable>();

function load(file: string, where: string): RawTable {
  const hit = cache.get(file);
  if (hit) return hit;
  const t = readJson<RawTable>(file);
  if (!t) throw new Error(`${where}: data file ${file} is missing (run its builder)`);
  if (t.version !== 1) throw new Error(`${where}: ${file} has data version ${t.version}, expected 1`);
  cache.set(file, t);
  return t;
}

export function deltaRows(spec: DeltaTable, where: string): { label: string; values: number[]; hint?: string }[] {
  const t = load(spec.file, where);
  const cell = (key: string): ((i: number) => string | number | null) => {
    if (key in t.constant) return () => t.constant[key];
    const c = t.columns.find((x) => x.key === key);
    if (!c) throw new Error(`${where}: ${spec.file} has no column '${key}'`);
    if (c.type === "cat") return (i) => (c.data[i] >= 0 ? c.values[c.data[i]] : null);
    return (i) => c.data[i];
  };
  const value = cell(spec.value);
  const groups = spec.groupBy.map(cell);
  const filters = Object.entries(spec.where ?? {}).map(([k, v]) => ({ get: cell(k), ok: new Set(Array.isArray(v) ? v : [v]) }));
  const out = new Map<string, { label: string; values: number[]; hint?: string }>();
  for (let i = 0; i < t.rows; i++) {
    if (!filters.every((f) => f.ok.has(String(f.get(i) ?? "")))) continue;
    const v = value(i);
    if (typeof v !== "number") continue;
    const parts = groups.map((g) => String(g(i) ?? "-"));
    const key = parts.join(" | ");
    let row = out.get(key);
    if (!row) out.set(key, (row = { label: spec.labels?.[key] ?? parts.join(" · "), values: [], hint: spec.hints?.[key] }));
    row.values.push(v);
  }
  if (!spec.only) return [...out.values()];
  return spec.only.map((k) => {
    const row = out.get(k);
    if (!row) throw new Error(`${where}: ${spec.file} has no rows for '${k}' (groups: ${[...out.keys()].join(", ")})`);
    return row;
  });
}
