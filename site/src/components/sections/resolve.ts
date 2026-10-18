// Build time: a mod's sections with their kinds, each source checked once by its kind's parseSource (errors name the
// mod and section), plus what a section card and a section page header show. The routes use these, never the raw
// manifest sections.
import { getMedia } from "@/lib/media";
import { sectionHref, type ModInfo } from "@/lib/mods";
import { getKind } from "./registry";
import type { AnyKind, Section, SectionProps } from "./types";

export interface ResolvedSection {
  section: Section;
  kind: AnyKind;
}

const cache = new Map<string, ResolvedSection[]>();

export function getSections(mod: ModInfo): ResolvedSection[] {
  const hit = cache.get(mod.id);
  if (hit) return hit;
  const out = mod.sections.map((def) => {
    const where = `${mod.id} section '${def.slug}' (kind ${def.kind})`;
    const kind = getKind(def.kind);
    const source = kind.parseSource ? kind.parseSource(def.source, where) : def.source;
    return { section: { ...def, source }, kind };
  });
  cache.set(mod.id, out);
  return out;
}

/** Static facts of the section plus the kind's computed ones. */
export const sectionStats = (mod: ModInfo, { section, kind }: ResolvedSection) => {
  const p: SectionProps = { mod, section };
  return [...(section.stats ?? []), ...(kind.summarize?.(p) ?? [])];
};

/** What a section's card shows: link, texts, facts, badge and image (section.thumb, else the kind's thumb). */
export function sectionCard(mod: ModInfo, r: ResolvedSection) {
  const { section, kind } = r;
  const own = section.thumb ? getMedia(mod.id, section.thumb)?.thumb.url : undefined;
  return {
    href: sectionHref(mod, section),
    title: section.title,
    description: section.description,
    stats: sectionStats(mod, r),
    badge: kind.badge,
    thumb: own ?? kind.thumb?.({ mod, section }),
  };
}
