// Build time: checks a story section's source once (errors name the mod and section) and counts its entries.
import { readChangelog } from "@/lib/changelog";
import { plural } from "@/lib/format";
import type { Stat } from "@/lib/define-mod";
import type { ModInfo } from "@/lib/mods";
import type { SectionProps, TocEntry } from "../types";
import type { Block, Chapter, StorySource } from "./types";

const BLOCKS = new Set<Block["type"]>(["p", "list", "parts", "figure", "gallery", "compare", "pairs", "mosaic", "steps", "facts", "bars", "deltas", "table", "sources"]);
const ID_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function parseStorySource(raw: unknown, where: string): StorySource {
  const s = raw as Partial<StorySource> | undefined;
  if (!s || typeof s !== "object") throw new Error(`${where}: story needs a source (StorySource)`);
  if (!["article", "timeline", "list"].includes(s.layout as string)) throw new Error(`${where}: story source.layout must be "article", "timeline" or "list"`);
  if (!Array.isArray(s.chapters)) throw new Error(`${where}: story source.chapters must be an array`);
  const tags = new Set((s.tags ?? []).map((t) => t.key));
  if (s.changelog) tags.add(s.changelog.tag);
  const ids = new Set<string>();
  for (const c of s.chapters) {
    if (!c || typeof c.title !== "string" || !ID_RE.test(c.id ?? "")) throw new Error(`${where}: every chapter needs a title and a dashed id (got '${c?.id}')`);
    if (ids.has(c.id)) throw new Error(`${where}: duplicate chapter id '${c.id}'`);
    ids.add(c.id);
    if (c.date && !/^\d{4}-\d{2}-\d{2}$/.test(c.date)) throw new Error(`${where}: chapter ${c.id} date must be YYYY-MM-DD`);
    for (const t of c.tags ?? []) if (!tags.has(t)) throw new Error(`${where}: chapter ${c.id} has unknown tag '${t}' (add it to source.tags)`);
    for (const b of c.blocks ?? []) {
      if (!BLOCKS.has(b?.type)) throw new Error(`${where}: chapter ${c.id} has an unknown block type '${(b as { type?: string })?.type}'`);
      if (b.type === "deltas" && !b.rows === !b.table) throw new Error(`${where}: chapter ${c.id}: a deltas block needs rows or table (one of them)`);
    }
  }
  if (s.layout === "timeline" && s.chapters.some((c) => !c.date)) throw new Error(`${where}: every timeline chapter needs a date`);
  return s as StorySource;
}

export function storySummary({ mod, section }: SectionProps<StorySource>): Stat[] {
  const s = section.source;
  const n = s.chapters.length;
  const out: Stat[] = [{ label: s.layout === "article" ? plural(n, "chapter", "chapters") : plural(n, "entry", "entries"), value: n }];
  if (s.changelog) {
    const r = readChangelog(mod.id).length;
    if (r) out.push({ label: plural(r, "revision", "revisions"), value: r });
  }
  return out;
}

/** The mod's changelog revisions as chapters (oldest first, like the chapters), when the source asks for them. */
export function changelogChapters(mod: ModInfo, src: StorySource): Chapter[] {
  if (!src.changelog) return [];
  const tag = src.changelog.tag;
  return [...readChangelog(mod.id)].reverse().filter((e) => e.date).map((e) => ({
    id: `revision-${e.revision}`,
    title: `Revision ${e.revision}`,
    date: e.date,
    tags: [tag],
    summary: "From the mod's changelog on mod.io.",
    blocks: [{ type: "list", items: e.items }],
  }));
}

/** An article's chapters for the page tabs' "On this page" menu (timelines and lists filter instead). */
export function storyToc({ mod, section }: SectionProps<StorySource>): TocEntry[] {
  const src = section.source;
  if (src.layout !== "article") return [];
  return [...src.chapters, ...changelogChapters(mod, src)].map((c) => ({ id: c.id, title: c.title }));
}
