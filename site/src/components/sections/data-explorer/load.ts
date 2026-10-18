// Build time: the data files of a data-explorer section, read once, plus what cards and headers show.
import { plural } from "@/lib/format";
import type { Stat } from "@/lib/define-mod";
import { readJson } from "@/lib/repo";
import type { SectionProps } from "../types";
import type { DatasetDef, DataExplorerSource, RawTable } from "./types";

export interface LoadedDataset {
  def: DatasetDef;
  /** URL slug and published file name stem */
  slug: string;
  path: string;
  table: RawTable;
  /** rows that pass / fail the source's outcome (undefined without an outcome column) */
  pass?: number;
  fail?: number;
}

const cache = new Map<string, LoadedDataset[]>();

export function loadDatasets({ mod, section }: SectionProps<DataExplorerSource>): LoadedDataset[] {
  const key = `${mod.id}/${section.slug}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const src = section.source;
  const out = src.datasets.map((def) => {
    const path = `${src.dir.replace(/\/$/, "")}/${def.file}`;
    const table = readJson<RawTable>(path);
    if (!table) throw new Error(`data-explorer ${key}: missing data file ${path} (run the builder)`);
    if (table.version !== 1) throw new Error(`data-explorer ${key}: ${path} has data version ${table.version}, expected 1`);
    let pass: number | undefined, fail: number | undefined;
    const o = def.outcome ?? src.outcome;
    if (o) {
      const col = table.columns.find((c) => c.key === o.key);
      if (col?.type === "cat") {
        const pi = col.values.indexOf(o.pass);
        pass = col.data.filter((v) => v === pi).length;
        fail = col.data.filter((v) => v >= 0 && v !== pi).length;
      } else if (o.key in table.constant) {
        pass = table.constant[o.key] === o.pass ? table.rows : 0;
        fail = table.rows - pass;
      }
    }
    return { def, slug: def.file.replace(/\.json$/, ""), path, table, pass, fail };
  });
  cache.set(key, out);
  return out;
}

/** Facts of one dataset: rows, pass share, date. */
export function datasetStats(d: LoadedDataset, src: DataExplorerSource): Stat[] {
  const u = d.def.unit ?? src.unit ?? { one: "row", many: "rows" };
  const o = d.def.outcome ?? src.outcome;
  const out: Stat[] = [{ label: plural(d.table.rows, u.one, u.many), value: d.table.rows.toLocaleString("en-US") }];
  if (d.pass != null && o) {
    const share = d.table.rows ? Math.round((d.pass / d.table.rows) * 1000) / 10 : 0;
    out.push({ label: o.passLabel.toLowerCase(), value: `${share}%`, tone: share === 100 ? "up" : "default" });
  }
  out.push({ label: "date", value: d.table.modified });
  return out;
}
