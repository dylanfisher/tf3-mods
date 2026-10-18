// Per-mod branding (tagline, accent) from branding/mods.js, the cover generator's data file. It is a plain
// browser script calling Square.register({...}) after branding/cover.js defines Square, so it is evaluated here
// as-is in a sandbox with a stub `window`: the same entries the covers use, nothing copied by hand.
import fs from "node:fs";
import vm from "node:vm";
import { repoPath } from "./repo.ts";

interface BrandingEntry {
  id: string;
  name: string;
  tagline?: string;
  accent?: string;
  series?: "state" | "fork" | "dev";
  deprecated?: boolean | string;
  order: number;
}

let cache: Map<string, BrandingEntry> | undefined;

export function getBranding(): Map<string, BrandingEntry> {
  if (cache) return cache;
  cache = new Map();
  try {
    const ctx: Record<string, unknown> = {};
    ctx.window = ctx;
    vm.createContext(ctx);
    for (const f of ["branding/cover.js", "branding/mods.js"]) {
      vm.runInContext(fs.readFileSync(repoPath(f), "utf8"), ctx, { filename: f, timeout: 2000 });
    }
    const mods = ((ctx.Square as { MODS?: Record<string, unknown>[] })?.MODS ?? []);
    mods.forEach((m, order) => {
      const id = String(m.id ?? "");
      if (!id) return;
      cache!.set(id, {
        id,
        name: String(m.name ?? id),
        tagline: typeof m.tagline === "string" ? m.tagline : undefined,
        accent: typeof m.accent === "string" ? m.accent : undefined,
        series: m.series as BrandingEntry["series"],
        deprecated: m.deprecated as BrandingEntry["deprecated"],
        order,
      });
    });
  } catch (e) {
    console.warn(`[site] branding/mods.js not readable: ${(e as Error).message}`);
  }
  return cache;
}
