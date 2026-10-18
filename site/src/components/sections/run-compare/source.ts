// Build time: checks a run-compare section's source (RunCompareSource) once; errors name the mod and section.
import type { RunCompareSource, UnitNames } from "./types";

/** What is compared when the source does not say: neutral wording (a mod names its own, e.g. towns). */
export const DEFAULT_UNIT: UnitNames = { one: "unit", many: "units" };
/** What a run is called when the source does not say. */
export const DEFAULT_RUN: UnitNames = { one: "run", many: "runs" };

export function parseRunCompareSource(raw: unknown, where: string): RunCompareSource {
  const s = raw as Partial<RunCompareSource> | undefined;
  if (!s || typeof s !== "object") throw new Error(`${where}: run-compare needs a source (RunCompareSource)`);
  const missing = [
    typeof s.dir !== "string" || !s.dir ? "dir" : "",
    !Array.isArray(s.summaryRows) ? "summaryRows" : "",
    !Array.isArray(s.unitRows) ? "unitRows" : "",
  ].filter(Boolean);
  if (missing.length) throw new Error(`${where}: run-compare source needs ${missing.join(", ")}`);
  if (s.unit && !(typeof s.unit.one === "string" && typeof s.unit.many === "string"))
    throw new Error(`${where}: run-compare source.unit must be { one, many }`);
  if (s.runName && !(typeof s.runName.one === "string" && typeof s.runName.many === "string"))
    throw new Error(`${where}: run-compare source.runName must be { one, many }`);
  if (s.order && s.order !== "viewer-first" && s.order !== "details-first")
    throw new Error(`${where}: run-compare source.order must be "viewer-first" or "details-first"`);
  return s as RunCompareSource;
}
