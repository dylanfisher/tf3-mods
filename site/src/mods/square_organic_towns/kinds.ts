// Organic Towns' own section kinds (used as "square_organic_towns/<name>" in mod.ts).
import { defineKind } from "@/components/sections/types";
import { readNameData } from "./namelab/data-file.ts";
import { MODES } from "./namelab/engine.ts";
import NameLab from "./namelab/NameLab.astro";

export const kinds = {
  /** The interactive Name lab (its data: namelab/data-file.ts). */
  "name-lab": defineKind({
    component: NameLab,
    summarize: () => {
      const d = readNameData();
      if (!d) return [];
      const towns = Object.values(d.towns ?? {}).reduce((n, t) => n + (t.names?.length ?? 0), 0);
      return [
        { label: "languages", value: Object.keys(d.lang ?? {}).length },
        { label: "generators", value: MODES.length },
        { label: "game names", value: towns.toLocaleString("en-US") },
      ];
    },
  }),
};
