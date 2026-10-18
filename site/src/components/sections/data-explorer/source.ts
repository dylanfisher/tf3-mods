// Build time: checks a data-explorer section's source (DataExplorerSource) once; errors name the mod and section.
import fs from "node:fs";
import { repoPath } from "@/lib/repo";
import { assertSlug } from "@/lib/slug";
import type { DataExplorerSource } from "./types";

const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);

export function parseDataExplorerSource(raw: unknown, where: string): DataExplorerSource {
  if (!isObj(raw)) throw new Error(`${where}: data-explorer needs a source (DataExplorerSource)`);
  const s = raw as Partial<DataExplorerSource>;
  if (typeof s.dir !== "string" || !s.dir) throw new Error(`${where}: data-explorer source.dir must be a repo-relative folder`);
  if (!fs.existsSync(repoPath(s.dir))) throw new Error(`${where}: data-explorer folder ${s.dir} does not exist (run its builder)`);
  if (!Array.isArray(s.datasets) || !s.datasets.length) throw new Error(`${where}: data-explorer source.datasets must list the data files`);
  const groups = new Set((s.groups ?? []).map((g) => g.key));
  for (const d of s.datasets) {
    if (!isObj(d) || typeof d.file !== "string" || typeof d.title !== "string" || typeof d.description !== "string")
      throw new Error(`${where}: every dataset needs file, title and description`);
    assertSlug(d.file, `${where}: dataset file`);
    if (d.group && !groups.has(d.group)) throw new Error(`${where}: dataset ${d.file} names unknown group '${d.group}'`);
  }
  if (s.outcome && !(typeof s.outcome.key === "string" && typeof s.outcome.pass === "string"))
    throw new Error(`${where}: data-explorer source.outcome must be { key, pass, passLabel, failLabel }`);
  return s as DataExplorerSource;
}
