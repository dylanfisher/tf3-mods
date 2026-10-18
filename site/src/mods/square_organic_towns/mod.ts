import { imageGrid, runCompare } from "../../components/sections/define.ts";
import { defineMod, withPreset } from "../../lib/define-mod.ts";
import { otCompare } from "./compare.ts";

const PLANS = "plans/square_organic_towns";

export default defineMod({
  id: "square_organic_towns",
  landing: "landing.mdx",
  sections: [
    runCompare({
      slug: "comparisons",
      title: "Map comparisons",
      description:
        "The same seed played with the mod and without it, or across mod versions: tour shots side by side, a slider and per-town numbers.",
      source: otCompare(`${PLANS}/compare`),
      // side-by-side viewer: the "view" preset (1280 px, lighter) is enough for two shots sharing the page width
      media: withPreset("view", [`${PLANS}/compare/*/*/*.jpg`]),
      width: "wide",
    }),
    {
      slug: "name-lab",
      title: "Name lab",
      description:
        "A playground for the generated town names: build a site from tags, generate names, compare generator ideas side by side and edit the word lists.",
      // data: plans/square_organic_towns/names/data.json (namelab/data-file.ts)
      kind: "square_organic_towns/name-lab",
      width: "wide",
    },
    imageGrid({
      slug: "street-plans",
      title: "Street-plan previews",
      description:
        "Offline renders of the street styles on synthetic terrain (flat, hillside, river, coast), of the town shapes and of the style the site picks on its own: filter, group, a style x terrain matrix and a zoomable viewer.",
      // previews.json (tools/ot_preview.py): set, style, terrain, variant, town shape and region of every SVG
      source: { manifest: `${PLANS}/svg/previews.json`, groupBy: "set", matrix: { rows: "style", cols: "terrain" } },
      // SVGs are published as they are; the "grid" preset only makes their raster thumbs smaller
      media: withPreset("grid", [`${PLANS}/svg/*.svg`, `${PLANS}/svg/shapes/*.svg`, `${PLANS}/svg/site/*.svg`]),
    }),
  ],
});
