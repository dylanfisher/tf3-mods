// The one URL-slug rule of the site: lowercase, letters and digits joined by single dashes, never underscores.
// Every route param, href builder and media output path goes through it, so mod ids and data folders keep their
// names (square_organic_towns, 2026-10-14_a-usa) while the URLs are dashed (/square-organic-towns/, 2026-10-14-a-usa).
// Plain TypeScript with only erasable syntax: scripts/media.mjs imports it (via media-core.ts) under Node.

/** A URL segment from any name: "square_organic_towns" -> "square-organic-towns". Keeps "." (versions, files). */
export function slugify(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9.]+/g, "-")
    .replace(/-*\.-*/g, ".")
    .replace(/^[-.]+|[-.]+$/g, "");
}

/** A valid URL segment: runs of lowercase letters and digits joined by single "-" or "." (no "_", no "--"). */
const SLUG_RE = /^[a-z0-9]+(?:[.-][a-z0-9]+)*$/;

/** Throws unless `s` is a valid slug (routes, defineMod); `noDot` for section slugs. */
export function assertSlug(s: string, what: string, { noDot = false }: { noDot?: boolean } = {}): string {
  if (!SLUG_RE.test(s) || (noDot && s.includes(".")))
    throw new Error(`${what}: bad URL slug '${s}' (lowercase letters, digits, "-"${noDot ? "" : ' and "."'}; use slugify())`);
  return s;
}

/** Site path from segments, each slugified: urlPath("square_organic_towns", "comparisons") -> "/square-organic-towns/comparisons/". */
export const urlPath = (...segments: string[]) => `/${segments.map(slugify).join("/")}/`;
