// The story blocks after the build resolved their images (Story.astro): what StoryBlocks / StoryList render.
import type { Block, Chapter, StoryImage } from "./types";

export interface ResolvedImage extends StoryImage {
  thumb: string;
  full: string;
  /** thumb width / height */
  w: number;
  h: number;
  /** full width */
  fw: number;
}

type DeltasBlock = Extract<Block, { type: "deltas" }>;

type Resolve<B> = B extends { type: "figure" }
  ? { type: "figure"; image: ResolvedImage }
  : B extends { type: "gallery" }
    ? { type: "gallery"; images: ResolvedImage[] }
    : B extends { type: "compare" }
      ? { type: "compare"; before: ResolvedImage & { label: string }; after: ResolvedImage & { label: string }; caption?: string }
      : B extends { type: "pairs" }
        ? { type: "pairs"; pairs: { before: ResolvedImage & { label: string }; after: ResolvedImage & { label: string }; caption?: string }[]; columns?: 1 | 2 }
      : B extends { type: "mosaic" }
        ? { type: "mosaic"; images: ResolvedImage[]; size?: "s" | "m" | "l"; lead?: boolean }
      : B extends { type: "deltas" }
        ? Omit<DeltasBlock, "table" | "rows"> & { rows: NonNullable<DeltasBlock["rows"]> }
        : B;

export type ResolvedBlock = Resolve<Block>;

export interface ResolvedChapter extends Omit<Chapter, "blocks"> {
  blocks: ResolvedBlock[];
  /** plain text of the chapter for search */
  text: string;
}

/** Blocks that need the client (state or pointer handling). */
export const isInteractive = (b: ResolvedBlock) =>
  b.type === "compare" || b.type === "pairs" || b.type === "mosaic" || b.type === "bars" || b.type === "deltas";
