// Typed section helpers for manifests (src/mods/<modId>/mod.ts): each sets the generic kind and types its `source`,
// so a manifest gets its kind's options checked by TypeScript (and again by the kind's parseSource at build time).
// Only erasable TypeScript with type-only imports: scripts/media.mjs imports the manifests with Node.
import type { SectionDef } from "../../lib/define-mod.ts";
import type { DataExplorerSource } from "./data-explorer/types.ts";
import type { ImageGridSource } from "./image-grid/types.ts";
import type { RunCompareSource } from "./run-compare/types.ts";
import { storyImages, type StorySource } from "./story/types.ts";

type Base = Omit<SectionDef, "kind" | "source">;

/** Game runs compared unit by unit: a list of comparisons, each a sub-page (run-compare/types.ts). */
export const runCompare = (s: Base & { source: RunCompareSource }): SectionDef => ({ ...s, kind: "run-compare" });

/** Filterable image grid with facets, matrix and lightbox (image-grid/types.ts). */
export const imageGrid = (s: Base & { source?: ImageGridSource }): SectionDef => ({ ...s, kind: "image-grid" });

/** Result tables with filters, a breakdown chart and a sortable table, one sub-page each (data-explorer/types.ts). */
export const dataExplorer = (s: Base & { source: DataExplorerSource }): SectionDef => ({ ...s, kind: "data-explorer" });

/**
 * A written page from typed blocks: article, timeline or cards (story/types.ts). The images its blocks show are added
 * to the section's media (the media build publishes them).
 */
export const story = (s: Base & { source: StorySource }): SectionDef => ({
  ...s,
  kind: "story",
  media: [...(s.media ?? []), ...storyImages(s.source)],
});

/** Not built yet: a notice plus its media. @public (no manifest uses it right now) */
export const placeholder = (s: Base): SectionDef => ({ ...s, kind: "placeholder" });
