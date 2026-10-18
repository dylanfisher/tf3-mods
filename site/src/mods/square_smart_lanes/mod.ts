// Smart Lanes (square_smart_lanes): landing + pictures first (twins side by side), then the numbers and how it was built.
// Sources: plans/square_smart_lanes/ (shots/, site/ with the picked screenshots, the bench pages, showcase.json,
// twins.json and build_data.py, plan docs, RESULTS.md), plans/square_stress_test/ (the bench), mods/square_smart_lanes/.
import { dataExplorer, imageGrid, runCompare, story } from "../../components/sections/define.ts";
import { defineMod, withPreset, type MediaSpec } from "../../lib/define-mod.ts";
import { behindTheScenes } from "./behind-the-scenes.ts";
import { benchSource } from "./bench.ts";
import { dataSource } from "./data.ts";
import { results } from "./results.ts";
import { showcase } from "./showcase.ts";
import { timeline } from "./timeline.ts";

const PLANS = "plans/square_smart_lanes";
const BENCH = `${PLANS}/site/bench`;
// The bench screenshots are mostly grass around the junction: sheets 1-3 were shot from high up (the builder already
// cut them to the middle 1 / 2.5), sheet 4 a little lower. Each declaration of them carries the same crop.
const benchShots = (preset: MediaSpec["preset"]): MediaSpec[] => [
  { glob: `${BENCH}/2026-10-13_*_s[123]/shots/*.jpg`, preset, crop: { zoom: 1.4 } },
  { glob: `${BENCH}/*_s4/shots/*.jpg`, preset, crop: { zoom: 1.25 } },
];

export default defineMod({
  id: "square_smart_lanes",
  landing: "landing.mdx",
  highlights: [
    { src: `${PLANS}/shots/01-ring-lanes.jpg`, caption: "Chained roundabouts in the Smart Lanes lane view", section: "showcase" },
    { src: `${BENCH}/2026-10-13_0610_s2/shots/g1a.jpg`, caption: "Smart Lanes: 42.9 km/h through the slip-lane T", section: "showcase" },
    { src: `${BENCH}/2026-10-13_0610_s2/shots/g1b.jpg`, caption: "Game lanes: 13.4 km/h through the same T", section: "showcase" },
    { src: `${PLANS}/shots/18-ring-mid-nodes.jpg`, caption: "Lane changes between a roundabout's arms", section: "showcase" },
    { src: `${PLANS}/shots/16-district-select.jpg`, caption: "A whole district's junctions at once", section: "showcase" },
    { src: `${PLANS}/shots/10-bench-map.jpg`, caption: "A test map of twin junctions", section: "twins" },
    { src: `${PLANS}/site/shots/2026-10-12-phase-arrows.jpg`, caption: "One light phase at a busy crossroads", section: "showcase" },
  ],
  sections: [
    story({
      slug: "showcase",
      title: "Showcase",
      description: "Twin junctions side by side, game lanes against Smart Lanes, with sliders; the lane view, whole districts at once, lights and the test maps.",
      source: showcase,
      media: benchShots("view"),
      thumb: `${BENCH}/2026-10-13_0610_s2/shots/g1a.jpg`,
      width: "wide",
    }),
    imageGrid({
      slug: "twins",
      title: "Every twin",
      description: "Every bench screenshot in one wall: each junction as the game left it, with Smart Lanes and with the test layouts, and its speed.",
      // twins.json: plans/square_smart_lanes/site/build_data.py (every bench shot with its twin's speed)
      source: { manifest: `${PLANS}/site/twins.json`, groupBy: "bench", matrix: { rows: "test", cols: "mode" }, view: "matrix", size: "s" },
      media: benchShots("grid"),
      width: "wide",
    }),
    story({
      slug: "results",
      title: "Results in charts",
      description: "Every junction type measured against the game's own lanes: what won, what lost and what made no difference.",
      source: results,
      media: benchShots("view"),
      thumb: `${PLANS}/shots/09-roundabout-top.jpg`,
    }),
    runCompare({
      slug: "bench-runs",
      title: "Bench runs",
      description: "The nine bench runs twin by twin: screenshots side by side or on a slider, and every set's speed, cars per minute and queues.",
      source: benchSource(`${PLANS}/site/bench`),
      media: benchShots("view"),
      width: "wide",
    }),
    imageGrid({
      slug: "gallery",
      title: "Screenshots",
      description: "Every screenshot: release captures, the tool and lane view in test sessions, and the bench twins.",
      // gallery.json: plans/square_smart_lanes/site/build_data.py (CURATED, PICKS and the bench shots)
      source: { manifest: `${PLANS}/site/gallery.json`, groupBy: "subject", matrix: { rows: "subject", cols: "view" }, view: "wall" },
      media: [...withPreset("grid", [`${PLANS}/shots/*.jpg`, `${PLANS}/site/shots/*.jpg`]), ...benchShots("grid")],
      width: "wide",
    }),
    story({
      slug: "behind-the-scenes",
      title: "Behind the scenes",
      description: "How it works, the choices, the problems and their fixes, the hunt for a faster roundabout, and the tests.",
      source: behindTheScenes,
      thumb: `${PLANS}/shots/17-district-panel.jpg`,
    }),
    story({
      slug: "timeline",
      title: "Timeline",
      description: "Seven days from a probe that read the game's roundabout lanes to the current revision, with every changelog entry.",
      source: timeline,
      thumb: `${PLANS}/shots/05-showcase-map.jpg`,
    }),
    dataExplorer({
      slug: "data",
      title: "Measurements",
      description: "Every bench and showcase pair, every twin, the junction audit and the slow-call lines from the game logs, and the test timings, as tables.",
      source: dataSource(`${PLANS}/site/data`),
      thumb: `${PLANS}/shots/10-bench-map.jpg`,
      width: "wide",
    }),
  ],
});
