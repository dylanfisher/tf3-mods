// The mod manifest: everything a microsite needs that is not already in the repo. Name, summary, cover, tagline,
// accent and the mod.io link are read from the mod's own files (see mods.ts), never repeated here.
// Plain data with erasable TypeScript only: scripts/media.mjs imports manifests directly with Node.
import type { MediaCrop, MediaPresetName } from "./media-core.ts";
import { assertSlug } from "./slug.ts";

/** A small fact shown on a section card or a page header: "towns 16", "runs 3". */
export interface Stat {
  label: string;
  value: string | number;
  /** optional color role */
  tone?: "default" | "up" | "down" | "warn" | "brand";
}

/** Content width of a page (theme.css --container-page / --container-wide). */
export type PageWidth = "page" | "wide";

/**
 * Images a section publishes: a repo-relative glob (Node fs.glob syntax, e.g. `plans/<modId>/svg/*.svg`), built with the
 * "default" preset, or a spec asking for a smaller preset (MEDIA_RECIPE.presets in media-core.ts: "view", "grid",
 * "wall") and an optional center crop for shots that are mostly empty ground. A source declared twice is built once,
 * with the larger preset and the crop any declaration gives (a crop belongs to the source); two different crops of one
 * source fail the media build.
 */
export type MediaGlob = string | MediaSpec;

export interface MediaSpec {
  glob: string;
  preset?: MediaPresetName;
  crop?: MediaCrop;
}

/** The glob of a media declaration. */
export const mediaGlobOf = (g: MediaGlob): string => (typeof g === "string" ? g : g.glob);

/** Gives every glob a preset (and crop): `withPreset("grid", ["a/*.jpg"])`. */
export const withPreset = (preset: MediaPresetName, globs: MediaGlob[], crop?: MediaCrop): MediaSpec[] =>
  globs.map((g) => ({ ...(typeof g === "string" ? { glob: g } : g), preset, ...(crop ? { crop } : {}) }));

export interface SectionDef {
  /** URL segment: /<mod-slug>/<slug>/. Lowercase letters, digits and dashes (src/lib/slug.ts), never underscores. */
  slug: string;
  title: string;
  /** one or two sentences for the section card and page header */
  description: string;
  /**
   * How the section renders. A generic kind from src/components/sections/registry.ts ("placeholder",
   * "image-grid", ...) or a mod-specific one registered in src/mods/<modId>/kinds.ts, written "<modId>/<name>".
   */
  kind: string;
  /**
   * Data the kind reads (repo-relative paths, options, build-time formatters). Its shape is up to the kind: the kind's
   * parseSource checks it once at build time (an error names the mod and section) and hands the typed value to its
   * component. Write generic sections with the typed helpers in src/components/sections/define.ts (runCompare,
   * imageGrid, placeholder), which type `source` for the kind.
   */
  source?: unknown;
  /** Images this section publishes; the media build processes them and the kind looks them up. */
  media?: MediaGlob[];
  /**
   * Card image (repo-relative path, processed by the media build), overriding the kind's thumb. Without either the
   * card shows generated title art (src/components/site/TitleArt.tsx).
   */
  thumb?: string;
  /** Static facts for the section card (a kind can add computed ones through its summarize()). */
  stats?: Stat[];
  /** Page width: "page" (default, 1100px) or "wide" (1400px, for side-by-side viewers). */
  width?: PageWidth;
}

export interface Highlight {
  src: string;
  caption?: string;
  /** slug of the section the image links to */
  section?: string;
}

export interface ModLink {
  label: string;
  href: string;
}

export interface ModManifest {
  /** modId: folder in mods/ */
  id: string;
  /** Landing copy next to mod.ts (default "landing.mdx"). */
  landing?: string;
  /** Research sections, in display order. */
  sections: SectionDef[];
  /**
   * Big images on the landing, above the copy (repo-relative sources, built with the "default" preset): the first one
   * large, the rest as a mosaic. Each may link to the section that tells more.
   */
  highlights?: Highlight[];
  /** Extra links shown in the hero next to mod.io. */
  links?: ModLink[];
}

export function defineMod(m: ModManifest): ModManifest {
  if (!/^[a-z0-9_]+$/.test(m.id)) throw new Error(`defineMod: bad modId '${m.id}'`);
  const seen = new Set<string>();
  for (const h of m.highlights ?? []) {
    if (h.section && !m.sections.some((s) => s.slug === h.section)) throw new Error(`defineMod ${m.id}: highlight ${h.src} links to unknown section '${h.section}'`);
  }
  for (const s of m.sections) {
    assertSlug(s.slug, `defineMod ${m.id}: section`, { noDot: true });
    if (seen.has(s.slug)) throw new Error(`defineMod ${m.id}: duplicate section slug '${s.slug}'`);
    seen.add(s.slug);
  }
  return m;
}

/** Repo-relative path of a mod's cover (the mod-covers skill renders it). */
export const coverPath = (modId: string) => `mods/${modId}/_metadata/0.png`;

/** Every media glob a manifest declares (cover first). Used by scripts/media.mjs. */
export function manifestMedia(m: ModManifest): MediaGlob[] {
  return [
    coverPath(m.id),
    ...(m.highlights ?? []).map((h) => h.src),
    ...m.sections.flatMap((s) => [...(s.thumb ? [s.thumb] : []), ...(s.media ?? [])]),
  ];
}
