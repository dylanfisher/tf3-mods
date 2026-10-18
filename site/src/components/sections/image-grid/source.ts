// Build time: checks an image-grid section's source (ImageGridSource) once; errors name the mod and section.
import type { ImageGridSource } from "./types";

const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);

export function parseImageGridSource(raw: unknown, where: string): ImageGridSource {
  if (raw == null) return {};
  if (!isObj(raw)) throw new Error(`${where}: image-grid source must be an object`);
  const bad = (field: string, want: string) => new Error(`${where}: image-grid source.${field} must be ${want}`);
  if (raw.manifest != null && typeof raw.manifest !== "string") throw bad("manifest", "a repo-relative path");
  if (raw.facets != null && !Array.isArray(raw.facets)) throw bad("facets", "an array of { key, label, values }");
  if (raw.groupBy != null && typeof raw.groupBy !== "string") throw bad("groupBy", "a facet key");
  if (raw.matrix != null && !(isObj(raw.matrix) && typeof raw.matrix.rows === "string" && typeof raw.matrix.cols === "string"))
    throw bad("matrix", "{ rows, cols } facet keys");
  if (raw.size != null && !["s", "m", "l"].includes(raw.size as string)) throw bad("size", '"s", "m" or "l"');
  if (raw.view != null && !["grid", "wall", "matrix"].includes(raw.view as string)) throw bad("view", '"grid", "wall" or "matrix"');
  if (raw.view === "matrix" && raw.matrix == null) throw bad("view", 'not "matrix" without source.matrix');
  const known = new Set(["manifest", "facets", "groupBy", "matrix", "size", "view"]);
  const extra = Object.keys(raw).filter((k) => !known.has(k));
  if (extra.length) throw new Error(`${where}: unknown image-grid source field(s) ${extra.join(", ")}`);
  return raw as ImageGridSource;
}
