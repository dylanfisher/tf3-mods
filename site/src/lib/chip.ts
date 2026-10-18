// The chip (pill) look, one place for React and Astro: list chips, run chips, tags, badges, the dashed "outline" pill
// (a reference run, "Coming soon", "Not released yet"). Pass extra classes to adjust size or color; cn merges them.
import { cn } from "@/lib/utils";

type ChipTone = "default" | "brand" | "warn" | "outline";

const TONES: Record<ChipTone, string> = {
  default: "bg-chip text-foreground",
  brand: "bg-brand text-on-brand font-semibold",
  warn: "bg-warn text-background",
  outline: "border border-dashed border-muted-foreground bg-transparent",
};

/** Classes of a chip; long data text (labels, names) also wants CHIP_CLIP. */
export const chipClass = (tone: ChipTone = "default", extra?: string) =>
  cn("inline-block rounded-full px-2 py-px text-tag whitespace-nowrap", TONES[tone], extra);

/** Cuts a long chip at 280px with an ellipsis (the chip is then aligned by its bottom edge, not the text baseline). */
export const CHIP_CLIP = "max-w-[280px] truncate";
