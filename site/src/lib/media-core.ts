// Shared by scripts/media.mjs (writes the media) and media.ts (pages look it up). Plain TypeScript with only
// erasable syntax so Node runs it directly (type stripping) from the build script.
import crypto from "node:crypto";
import path from "node:path";
import { slugify } from "./slug.ts";

/**
 * How every image is made. The cache key is a hash of this object: change a value (or bump `rev` after a change in
 * media.mjs's processing code) and every source is processed again on the next run.
 *
 * Presets: a section asks for smaller outputs with a media spec `{ glob, preset, crop }` (MediaSpec in define-mod.ts);
 * a plain glob string uses "default". A source declared by several sections is built once, with the largest preset
 * asked for (by fullWidth, then quality).
 */
export const MEDIA_RECIPE = {
  rev: 4,
  format: "webp",
  effort: 4,
  alphaQuality: 90,
  /** SVG rasterizing density for the thumb (dpi) */
  svgDensity: 144,
  presets: {
    /** pages that show one image across the page (figures, sliders, landing highlights) */
    default: { thumbWidth: 480, fullWidth: 1600, quality: 80, thumbQuality: 78 },
    /** side-by-side viewers and comparison pages: two images share the width */
    view: { thumbWidth: 480, fullWidth: 1280, quality: 72, thumbQuality: 72 },
    /** grids with a lightbox: small thumbs, the lightbox's full image a little smaller */
    grid: { thumbWidth: 360, fullWidth: 1280, quality: 70, thumbQuality: 68 },
    /** walls of hundreds of images: tiny thumbs, light full images */
    wall: { thumbWidth: 320, fullWidth: 1024, quality: 64, thumbQuality: 62 },
  },
} as const;

export type MediaPresetName = keyof typeof MEDIA_RECIPE.presets;

/**
 * Cut a source to its middle before resizing, for shots that are mostly empty sky or grass: the kept part is
 * 1 / zoom of the width and height, centered on (x, y) as fractions of the frame (default the center).
 */
export interface MediaCrop {
  zoom: number;
  x?: number;
  y?: number;
}

/** What one source is built with: the preset name and the crop (cache key part of an entry). */
interface MediaVariantSpec {
  preset: MediaPresetName;
  crop?: MediaCrop;
}

export const variantKey = (v: MediaVariantSpec) => JSON.stringify([v.preset, v.crop ?? null]);

/** The larger of two presets (fullWidth, then quality), so one output serves every section that shows a source. */
export function largerPreset(a: MediaPresetName, b: MediaPresetName): MediaPresetName {
  const pa = MEDIA_RECIPE.presets[a], pb = MEDIA_RECIPE.presets[b];
  if (pa.fullWidth !== pb.fullWidth) return pa.fullWidth > pb.fullWidth ? a : b;
  return pa.quality >= pb.quality ? a : b;
}

/** The crop box of a source of w x h: integer pixels inside the frame. */
export function cropBox(w: number, h: number, c: MediaCrop): { left: number; top: number; width: number; height: number } {
  const zoom = Math.max(1, c.zoom);
  const width = Math.max(1, Math.round(w / zoom)), height = Math.max(1, Math.round(h / zoom));
  const clamp = (v: number, max: number) => Math.min(Math.max(0, Math.round(v)), max);
  return {
    left: clamp((c.x ?? 0.5) * w - width / 2, w - width),
    top: clamp((c.y ?? 0.5) * h - height / 2, h - height),
    width,
    height,
  };
}

export const recipeHash = (): string =>
  crypto.createHash("sha1").update(JSON.stringify(MEDIA_RECIPE)).digest("hex").slice(0, 12);

/** Site URL of the media folder; its files live in site/public/media/. */
const MEDIA_URL = "/media";
export const MEDIA_DIR = `public${MEDIA_URL}`; // relative to site/
export const MEDIA_CACHE = ".cache/media.json"; // relative to site/

/** URL of one output: mediaUrl("square-organic-towns/svg/hill", ".thumb.webp"). */
export const mediaUrl = (stem: string, suffix: string) => `${MEDIA_URL}/${stem}${suffix}`;

export interface MediaVariant {
  url: string; // site URL, e.g. /media/square-organic-towns/compare/2026-10-14-a-usa/mod-0710/01-tour.webp
  width: number;
  height: number;
  bytes: number;
}

export interface MediaEntry {
  mod: string;
  src: string; // repo-relative source path
  hash: string; // sha1 of the source content
  bytesIn: number;
  /** variantKey() of the preset and crop it was built with (older entries: none, built again) */
  variant?: string;
  full: MediaVariant;
  thumb: MediaVariant; // same as full when the source is small or an SVG
}

export interface MediaCache {
  /** recipeHash() of the run that wrote it; another hash means everything is processed again */
  recipe: string;
  entries: Record<string, MediaEntry>; // key: entryKey(mod, src)
}

export const entryKey = (mod: string, src: string) => `${mod}:${src}`;

/** A repo-relative source path with its mods/<mod>/ or plans/<mod>/ prefix dropped (forward slashes). */
export function stripModPrefix(mod: string, src: string): string {
  const rel = src.split(path.sep).join("/");
  for (const prefix of [`mods/${mod}/`, `plans/${mod}/`]) {
    if (rel.startsWith(prefix)) return rel.slice(prefix.length);
  }
  return rel;
}

/**
 * Output path (no extension) under media/: the mod slug, then the source path without its mod prefix
 * (stripModPrefix), every segment slugified like any site URL (src/lib/slug.ts): no underscores, lower case.
 */
export function mediaStem(mod: string, src: string): string {
  const segs = stripModPrefix(mod, src).replace(/\.[^./]+$/, "").split("/").map(slugify);
  return [slugify(mod), ...segs].join("/");
}

export const isSvg = (src: string) => /\.svg$/i.test(src);
export const RASTER_RE = /\.(png|jpe?g|webp|gif|tiff?|avif)$/i;
