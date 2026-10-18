// Generic kind "story": a written page made of typed blocks, shown as an article (contents list), a filterable
// timeline or a list of expandable entries. Text is plain with inline markup (**bold**, `code`; components/site/
// Inline.tsx), never HTML. Only erasable TypeScript: manifests import it through sections/define.ts under Node.
import type { MediaSpec } from "../../../lib/define-mod.ts";
import type { MediaPresetName } from "../../../lib/media-core.ts";

/** An image of the media build: repo-relative source path (declared in the section's media by the story() helper). */
export interface StoryImage {
  src: string;
  caption?: string;
}

/** One series of a bar chart block (components/site/charts/BarChart.tsx). */
export interface StoryBarSeries {
  label: string;
  tone: "pass" | "fail";
}

export type Block =
  /** a paragraph */
  | { type: "p"; text: string }
  | { type: "list"; items: string[]; ordered?: boolean }
  /** labelled paragraphs: Symptom / Cause / Fix, Decision / Why ... */
  | { type: "parts"; parts: { label: string; text: string }[] }
  | ({ type: "figure" } & StoryImage)
  /** several images in a row (two or three columns) */
  | { type: "gallery"; images: StoryImage[] }
  /** two images of one view over each other with a slider */
  | { type: "compare"; before: StoryImage & { label: string }; after: StoryImage & { label: string }; caption?: string }
  /** several before / after sliders in a grid (one or two columns): twins side by side, each with its own caption */
  | { type: "pairs"; pairs: StoryPair[]; columns?: 1 | 2 }
  /**
   * a wall of images in justified rows (components/site/Mosaic.tsx): caption on hover, a lightbox. Built with
   * the "grid" preset unless `preset` says otherwise; `lead` shows the first image across the width.
   */
  | { type: "mosaic"; images: StoryImage[]; size?: "s" | "m" | "l"; lead?: boolean; preset?: MediaPresetName }
  /** a numbered flow of steps (a pipeline) */
  | { type: "steps"; steps: { title: string; text: string }[] }
  /** key numbers as tiles */
  | { type: "facts"; facts: { label: string; value: string; note?: string }[] }
  /** a horizontal bar chart: "share" splits each row into pass / fail, "value" compares totals */
  | {
      type: "bars";
      title: string;
      series: StoryBarSeries[];
      rows: { label: string; values: number[]; hint?: string }[];
      mode?: "share" | "value";
      unit?: string;
      digits?: number;
      rowHeader?: string;
      footer?: string;
    }
  /**
   * differences that go either way (A minus B per pair) as a diverging chart (components/site/charts/DeltaChart.tsx):
   * per row a bar to the mean and a dot per value; `better` says which sign is good (default "higher"). The rows are
   * written here (`rows`) or read at build time from a data-explorer data file (`table`, tools/site_table.py format),
   * so measured numbers stay in the builder's output instead of being copied into the manifest.
   */
  | {
      type: "deltas";
      title: string;
      rows?: DeltaRows;
      table?: DeltaTable;
      better?: "higher" | "lower";
      labels?: { better: string; worse: string };
      unit?: string;
      digits?: number;
      rowHeader?: string;
      footer?: string;
    }
  /** a small table (cells are inline markup) */
  | { type: "table"; head: string[]; rows: string[][]; caption?: string }
  /** where the facts come from (plan docs, logs): plain references, shown small */
  | { type: "sources"; items: string[] };

/** One before / after slider of a pairs block. */
export interface StoryPair {
  before: StoryImage & { label: string };
  after: StoryImage & { label: string };
  caption?: string;
}

type DeltaRows = { label: string; values: number[]; hint?: string }[];

/** Rows of a deltas block from a data file: one row per distinct value of the groupBy columns. */
export interface DeltaTable {
  /** repo-relative data file (tools/site_table.py, version 1) */
  file: string;
  /** numeric column holding one difference per table row */
  value: string;
  /** columns whose values (joined with " | ") make one chart row; rows keep the file's order of first appearance */
  groupBy: string[];
  /** keep only table rows whose column has this value (or one of these values) */
  where?: Record<string, string | string[]>;
  /** chart row label per group key ("cht | Smart Lanes vs Game lanes"); default: the values joined with " · " */
  labels?: Record<string, string>;
  /** muted second line per group key */
  hints?: Record<string, string>;
  /** keep only these group keys, in this order (default: every group, in data order) */
  only?: string[];
}

export interface Chapter {
  /** anchor id: lowercase letters, digits and dashes */
  id: string;
  title: string;
  /** YYYY-MM-DD (timeline order; shown next to the title) */
  date?: string;
  /** keys of source.tags */
  tags?: string[];
  /** one or two sentences shown before the blocks (and alone in a collapsed entry) */
  summary?: string;
  blocks?: Block[];
}

export interface StorySource {
  /**
   * "article": chapters in order with a contents list. "timeline": dated entries on a rail, filter by tag, newest or
   * oldest first. "list": entries with title, tags and summary that open to their blocks, filter by tag.
   */
  layout: "article" | "timeline" | "list";
  /** paragraphs above everything (inline markup) */
  intro?: string[];
  /** tag keys and labels, in filter order */
  tags?: { key: string; label: string }[];
  /** timeline: add the mod's changelog (mods/<id>/_metadata/description.html) as entries with this tag */
  changelog?: { tag: string };
  chapters: Chapter[];
}

/**
 * Every image the story's blocks show, with the media preset each needs (the story() helper adds them to the section's
 * media): figures "default", galleries, sliders and pairs "view", mosaics their own preset ("grid" by default).
 */
export function storyImages(s: StorySource): MediaSpec[] {
  const out: MediaSpec[] = [];
  const add = (preset: MediaPresetName, ...srcs: string[]) => { for (const glob of srcs) out.push({ glob, preset }); };
  for (const c of s.chapters)
    for (const b of c.blocks ?? []) {
      if (b.type === "figure") add("default", b.src);
      else if (b.type === "gallery") add("view", ...b.images.map((i) => i.src));
      else if (b.type === "compare") add("view", b.before.src, b.after.src);
      else if (b.type === "pairs") add("view", ...b.pairs.flatMap((p) => [p.before.src, p.after.src]));
      else if (b.type === "mosaic") add(b.preset ?? "grid", ...b.images.map((i) => i.src));
    }
  return out;
}
