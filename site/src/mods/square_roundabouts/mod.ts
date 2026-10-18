// Roundabouts & Interchanges (square_roundabouts): landing + pictures first, then how it was built. Sources:
// plans/square_roundabouts/ (shots/, site/ with the picked screenshots, the layout drawings and build_data.py, plan
// docs, probe tables), mods/square_roundabouts/.
import { dataExplorer, imageGrid, story } from "../../components/sections/define.ts";
import { defineMod, withPreset } from "../../lib/define-mod.ts";
import { behindTheScenes } from "./behind-the-scenes.ts";
import { probeSource } from "./probe.ts";
import { showcase } from "./showcase.ts";
import { timeline } from "./timeline.ts";

const PLANS = "plans/square_roundabouts";

export default defineMod({
  id: "square_roundabouts",
  landing: "landing.mdx",
  highlights: [
    { src: `${PLANS}/shots/20-horizon-mix.jpg`, caption: "Every entry, all the way to the horizon", section: "showcase" },
    { src: `${PLANS}/shots/18-planet-topdown.jpg`, caption: "The whole test map from high above", section: "showcase" },
    { src: `${PLANS}/shots/03-magic-closeup.jpg`, caption: "The Magic Roundabout", section: "showcase" },
    { src: `${PLANS}/shots/24-interchange-grid.jpg`, caption: "Every highway interchange layout and size", section: "showcase" },
    { src: `${PLANS}/shots/15-oblique-hamburger.jpg`, caption: "A road straight through the middle", section: "showcase" },
    { src: `${PLANS}/shots/14-top-down-variety.jpg`, caption: "Planted islands, a hamburger and a channelized junction", section: "showcase" },
    { src: `${PLANS}/shots/21-interchange-oblique.jpg`, caption: "A row of roundabout interchanges", section: "showcase" },
  ],
  sections: [
    story({
      slug: "showcase",
      title: "Showcase",
      description: "Whole fields of roundabouts and interchanges, the Magic Roundabout, before and after sliders and traffic, all from the game.",
      source: showcase,
      thumb: `${PLANS}/shots/20-horizon-mix.jpg`,
      width: "wide",
    }),
    imageGrid({
      slug: "every-layout",
      title: "Every layout",
      description: "176 plan drawings straight from the mod's own geometry: shape by size, lanes by arms, islands, slip lanes and every interchange, side by side at one scale.",
      // layouts.json + layouts/*.svg: plans/square_roundabouts/site/layouts.py (run by build_data.py)
      source: { manifest: `${PLANS}/site/layouts.json`, groupBy: "sweep", matrix: { rows: "row", cols: "col" }, view: "matrix", size: "s" },
      media: withPreset("grid", [`${PLANS}/site/layouts/*.svg`]),
      thumb: `${PLANS}/site/layouts/shape-scale-oval-15-l.svg`,
      width: "wide",
    }),
    imageGrid({
      slug: "gallery",
      title: "Screenshots",
      description: "Every screenshot: release captures and test sessions, filterable by subject, view and date.",
      // gallery.json: plans/square_roundabouts/site/build_data.py (captions of shots/ + site/shots/shots.json)
      source: { manifest: `${PLANS}/site/gallery.json`, groupBy: "subject", matrix: { rows: "subject", cols: "view" }, view: "wall" },
      media: withPreset("grid", [`${PLANS}/shots/*.jpg`, `${PLANS}/site/shots/2026-*.jpg`, `${PLANS}/site/shots/2026-*.png`]),
      width: "wide",
    }),
    story({
      slug: "behind-the-scenes",
      title: "Behind the scenes",
      description: "How it works, the choices and their costs, the problems and their fixes, the hunt for a negative zero, and the tests.",
      source: behindTheScenes,
      thumb: `${PLANS}/shots/25-parclo-diamond.jpg`,
    }),
    story({
      slug: "timeline",
      title: "Timeline",
      description: "Eight days from the first look at the game's roundabout to revision 7, with every changelog entry.",
      source: timeline,
      thumb: `${PLANS}/shots/18-planet-topdown.jpg`,
    }),
    dataExplorer({
      slug: "data",
      title: "Probe data",
      description: "Every run of the placement probe as a filterable table (about 44,000 answers from the game), plus the offline test timings.",
      source: probeSource(`${PLANS}/site/data`),
      thumb: `${PLANS}/shots/24-interchange-grid.jpg`,
      width: "wide",
    }),
  ],
});
