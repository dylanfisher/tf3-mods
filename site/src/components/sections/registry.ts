// Section kinds: how a manifest section renders. Generic kinds live here; a mod adds its own in
// src/mods/<modId>/kinds.ts (export const kinds = { <name>: defineKind({...}) }) and refers to them as "<modId>/<name>".
import { getMediaGlob } from "@/lib/media";
import { plural } from "@/lib/format";
import DataExplorerList from "./data-explorer/DataExplorerList.astro";
import DataExplorerView from "./data-explorer/DataExplorerView.astro";
import { datasetStats, loadDatasets } from "./data-explorer/load";
import { parseDataExplorerSource } from "./data-explorer/source";
import ImageGrid from "./image-grid/ImageGrid.astro";
import { parseImageGridSource } from "./image-grid/source";
import Placeholder from "./Placeholder.astro";
import { entryStats, loadEntries } from "./run-compare/load";
import RunCompareBrowser from "./run-compare/RunCompareBrowser.astro";
import RunCompareView from "./run-compare/RunCompareView.astro";
import { DEFAULT_RUN, parseRunCompareSource } from "./run-compare/source";
import { parseStorySource, storySummary, storyToc } from "./story/source";
import Story from "./story/Story.astro";
import { defineKind, type AnyKind, type SectionProps } from "./types";

const mediaCount = ({ mod, section }: SectionProps) => {
  const n = section.media ? getMediaGlob(mod.id, section.media).length : 0;
  return n ? [{ label: plural(n, "image", "images"), value: n }] : [];
};
const firstThumb = ({ mod, section }: SectionProps) =>
  section.media ? getMediaGlob(mod.id, section.media)[0]?.thumb.url : undefined;

const generic: Record<string, AnyKind> = {
  /** Not built yet: notice + a preview of the section's media. */
  placeholder: defineKind({ component: Placeholder, summarize: mediaCount, thumb: firstThumb, badge: "Coming soon" }),
  /**
   * Filterable grid of the section's media with a lightbox: search, a filter per facet, group by a facet, sizes and
   * an optional rows x columns matrix. source: ImageGridSource (image-grid/types.ts, all optional). Without a
   * manifest the folders are the facet.
   */
  "image-grid": defineKind({ parseSource: parseImageGridSource, component: ImageGrid, summarize: mediaCount, thumb: firstThumb }),
  /**
   * Game runs compared unit by unit: a filterable list of comparisons, each a sub-page with A / B picking, side by
   * side, slider, all runs, summary and per-unit tables. source: RunCompareSource (run-compare/types.ts).
   */
  "run-compare": defineKind({
    parseSource: parseRunCompareSource,
    component: RunCompareBrowser,
    itemComponent: RunCompareView,
    summarize: (p) => {
      const e = loadEntries(p);
      const runs = e.reduce((n, x) => n + x.runs.length, 0);
      const rn = p.section.source.runName ?? DEFAULT_RUN;
      return [{ label: plural(e.length, "comparison", "comparisons"), value: e.length }, { label: plural(runs, rn.one, rn.many), value: runs }];
    },
    thumb: (p) => loadEntries(p)[0]?.thumb?.thumb,
    items: (p) => loadEntries(p).map((e) => ({
      slug: e.slug, title: e.h1, description: e.description, stats: entryStats(e), thumb: e.thumb?.thumb, data: e,
    })),
  }),
  /**
   * Result tables (probe runs, test timings ...) from a builder (tools/site_table.py): the section page lists them with
   * a pass / fail overview chart; each table is a sub-page with filters, a breakdown chart and a sortable table.
   * source: DataExplorerSource (data-explorer/types.ts).
   */
  "data-explorer": defineKind({
    parseSource: parseDataExplorerSource,
    component: DataExplorerList,
    itemComponent: DataExplorerView,
    summarize: (p) => {
      const sets = loadDatasets(p);
      // rows in the section's unit only (tables with a unit of their own, e.g. search jobs or tests, are not added in)
      const rows = sets.reduce((n, d) => n + (d.def.unit ? 0 : d.table.rows), 0);
      const u = p.section.source.unit ?? { one: "row", many: "rows" };
      return [{ label: plural(sets.length, "table", "tables"), value: sets.length }, { label: plural(rows, u.one, u.many), value: rows.toLocaleString("en-US") }];
    },
    items: (p) => loadDatasets(p).map((d) => ({
      slug: d.slug, title: d.def.title, description: d.def.description, stats: datasetStats(d, p.section.source), data: d,
    })),
    files: (p) => loadDatasets(p).map((d) => ({ name: d.def.file, path: d.path })),
  }),
  /**
   * A written page from typed blocks (paragraphs, lists, figures, before / after sliders, step flows, facts, charts,
   * tables): an article with a contents list, a filterable timeline (optionally with the mod's changelog) or a grid of
   * cards. source: StorySource (story/types.ts).
   */
  story: defineKind({ parseSource: parseStorySource, component: Story, summarize: storySummary, thumb: firstThumb, toc: storyToc }),
};

const modKinds = import.meta.glob<{ kinds: Record<string, AnyKind> }>("../../mods/*/kinds.ts", { eager: true });

const kinds: Record<string, AnyKind> = { ...generic };
for (const [file, mod] of Object.entries(modKinds)) {
  const modId = file.split("/").at(-2)!;
  for (const [name, def] of Object.entries(mod.kinds)) kinds[`${modId}/${name}`] = def;
}

export function getKind(kind: string): AnyKind {
  const k = kinds[kind];
  if (!k) throw new Error(`Unknown section kind '${kind}'. Known: ${Object.keys(kinds).join(", ")}`);
  return k;
}
