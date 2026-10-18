// Page-side lookup of the media built by scripts/media.mjs (site/.cache/media.json). Build time only.
import fs from "node:fs";
import path from "node:path";
import { entryKey, MEDIA_CACHE, type MediaCache, type MediaEntry } from "./media-core.ts";
import { mediaGlobOf, type MediaGlob } from "./define-mod.ts";
import { SITE_ROOT } from "./repo.ts";

export type { MediaEntry } from "./media-core.ts";

let cache: MediaCache | undefined;
const warned = new Set<string>();

function load(): MediaCache {
  if (cache) return cache;
  try {
    cache = JSON.parse(fs.readFileSync(path.join(SITE_ROOT, MEDIA_CACHE), "utf8")) as MediaCache;
  } catch {
    cache = { recipe: "", entries: {} };
    console.warn("[site] no media built yet: run `make site-media`");
  }
  return cache;
}

/** One processed image by its repo-relative source path, or undefined (with a warning unless optional). */
export function getMedia(mod: string, src: string, opts: { optional?: boolean } = {}): MediaEntry | undefined {
  const e = load().entries[entryKey(mod, src)];
  if (!e && !opts.optional && !warned.has(src)) {
    warned.add(src);
    console.warn(`[site] media not built: ${src} (declare it in the mod manifest, then make site-media)`);
  }
  return e;
}

/** Every processed image of a mod whose source matches one of the globs (or media specs), in glob order then path order. */
export function getMediaGlob(mod: string, globs: MediaGlob | MediaGlob[]): MediaEntry[] {
  const all = Object.values(load().entries).filter((e) => e.mod === mod);
  const out: MediaEntry[] = [];
  const seen = new Set<string>();
  for (const spec of Array.isArray(globs) ? globs : [globs]) {
    const g = mediaGlobOf(spec);
    const hits = all.filter((e) => !seen.has(e.src) && path.matchesGlob(e.src, g));
    hits.sort((a, b) => a.src.localeCompare(b.src, "en", { numeric: true }));
    for (const h of hits) {
      seen.add(h.src);
      out.push(h);
    }
  }
  return out;
}
