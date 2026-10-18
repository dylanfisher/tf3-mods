// Loads every mod manifest (src/mods/*/mod.ts) and enriches it with the metadata the repo already has.
import type { MarkdownInstance } from "astro";
import { getBranding } from "./branding.ts";
import { coverPath, type ModManifest, type SectionDef } from "./define-mod.ts";
import { getMedia, type MediaEntry } from "./media.ts";
import { readJson } from "./repo.ts";
import { assertSlug, slugify, urlPath } from "./slug.ts";

export interface ModInfo {
  id: string;
  /** URL segment: the modId slugified (square_organic_towns -> square-organic-towns) */
  slug: string;
  manifest: ModManifest;
  name: string;
  summary: string;
  /** branding/mods.js tagline, else the modinfo summary */
  tagline: string;
  accent?: string;
  cover?: MediaEntry;
  revision?: number;
  modio?: { id: number; url: string };
  sections: SectionDef[];
  href: string;
}

interface ModInfoJson { name?: string; summary?: string }
interface ModJson { revision?: number }
interface ModioState { [modId: string]: { modioId?: number } }
interface ModioProfiles { source?: string; mods?: { slug: string; modioId: number; modId?: string }[] }

/**
 * The publisher on mod.io, from branding/modio_profiles.json (`source`: the profile page make more-from reads): the
 * profile URL (footer) and the game's URL that mod pages hang off (<game>/m/<mod.io slug>).
 */
export function getSiteProfile(): { profileUrl?: string; gameUrl?: string } {
  const src = readJson<ModioProfiles>("branding/modio_profiles.json")?.source;
  const game = src?.match(/^(https:\/\/[^/]+\/g\/[^/]+)\//)?.[1];
  return { profileUrl: src, gameUrl: game };
}

// mod.io's own rule (tools/more_from.py slugify()): mod.io name ids are the lowercased name, non-alphanumerics -> "-".
// Not a site URL: site slugs use slugify() from ./slug.ts.
const modioSlug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

const manifests = import.meta.glob<{ default: ModManifest }>("../mods/*/mod.ts", { eager: true });
const landings = import.meta.glob<MarkdownInstance<Record<string, unknown>>>("../mods/*/*.mdx");

let all: ModInfo[] | undefined;

export function getMods(): ModInfo[] {
  if (all) return all;
  const branding = getBranding();
  const state = readJson<ModioState>("branding/modio_state.json") ?? {};
  const profiles = readJson<ModioProfiles>("branding/modio_profiles.json")?.mods ?? [];
  const { gameUrl } = getSiteProfile();
  all = Object.entries(manifests).map(([file, mod]) => {
    const m = mod.default;
    const folder = file.split("/").at(-2);
    if (folder !== m.id) throw new Error(`${file}: id '${m.id}' does not match its folder '${folder}'`);
    const info = readJson<ModInfoJson>(`mods/${m.id}/_metadata/modinfo.json`);
    if (!info) throw new Error(`${file}: mods/${m.id}/_metadata/modinfo.json does not exist`);
    const b = branding.get(m.id);
    const name = info.name ?? m.id;
    const modioId = state[m.id]?.modioId ?? profiles.find((p) => p.modId === m.id)?.modioId;
    const slug = profiles.find((p) => p.modId === m.id || p.modioId === modioId)?.slug ?? modioSlug(name);
    return {
      id: m.id,
      slug: slugify(m.id),
      manifest: m,
      name,
      summary: info.summary ?? "",
      tagline: b?.tagline ?? info.summary ?? "",
      accent: b?.accent,
      cover: getMedia(m.id, coverPath(m.id), { optional: true }),
      revision: readJson<ModJson>(`mods/${m.id}/mod.json`)?.revision,
      modio: modioId && gameUrl ? { id: modioId, url: `${gameUrl}/m/${slug}` } : undefined,
      sections: m.sections,
      href: urlPath(m.id),
    };
  });
  const slugs = new Map<string, string>();
  for (const m of all) {
    const prev = slugs.get(m.slug);
    if (prev) throw new Error(`mods ${prev} and ${m.id} share the URL slug '${m.slug}'`);
    slugs.set(m.slug, m.id);
  }
  // Cover-gallery order (branding/mods.js), then the rest by name.
  const rank = (m: ModInfo) => branding.get(m.id)?.order ?? Number.MAX_SAFE_INTEGER;
  all.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
  return all;
}

export async function getLanding(mod: ModInfo) {
  const key = `../mods/${mod.id}/${mod.manifest.landing ?? "landing.mdx"}`;
  const load = landings[key];
  return load ? (await load()).Content : undefined;
}

// Every site URL is built here (or with urlPath from ./slug.ts): segments are slugified, never underscores.
export const sectionHref = (mod: ModInfo, s: SectionDef) => urlPath(mod.slug, s.slug);
/** URL of a section's sub-page (KindDef.items in src/components/sections/types.ts). */
export const itemHref = (mod: ModInfo, s: SectionDef, item: { slug: string }) => urlPath(mod.slug, s.slug, item.slug);
/** URL of a data file a section publishes (KindDef.files): /data/<mod-slug>/<section>/<name>, no trailing slash. */
export const dataFileHref = (mod: ModInfo, s: SectionDef, name: string) =>
  `/data/${mod.slug}/${slugify(s.slug)}/${assertSlug(name, `${mod.id}/${s.slug} data file`)}`;
