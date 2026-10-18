// Smart Lanes: "Results in charts" (generic story kind, article layout). The charts read their pairs from the
// builder's data files at build time (plans/square_smart_lanes/site/data/bench-pairs.json, showcase-pairs.json, written
// by plans/square_smart_lanes/site/build_data.py from the game logs); the sentences follow plans/square_smart_lanes/
// RESULTS.md "Verdicts" and plans/square_stress_test/BENCH.md / SHOWCASE.md.
import type { StorySource } from "../../components/sections/story/types.ts";

const DATA = "plans/square_smart_lanes/site/data";
const PAIRS = `${DATA}/bench-pairs.json`;
const SHOW = `${DATA}/showcase-pairs.json`;
const BENCH = "plans/square_smart_lanes/site/bench";
const VS = "Smart Lanes vs Game lanes";

const MAIN = [
  `Sheet 2 | cht | ${VS}`,
  `Sheet 2 | dia | ${VS}`,
  `Sheet 3 | lt22 | ${VS}`,
  `Sheet 3 | lx | ${VS}`,
  `Sheet 1 | rb4 | ${VS}`,
  `Sheet 1 | drop | ${VS}`,
];
const MAIN_LABELS: Record<string, string> = {
  [MAIN[0]]: "Channelized T (slip lanes)",
  [MAIN[1]]: "Diamond interchange",
  [MAIN[2]]: "Lit T-junction, 2 x 2 lanes",
  [MAIN[3]]: "Lit crossroads (2x2, 3x3, 3x2)",
  [MAIN[4]]: "Roundabout, 2 lanes, 4 arms",
  [MAIN[5]]: "Lane drop, 3 to 2 lanes",
};
const GROUP = ["bench", "test", "compare"];

export const results: StorySource = {
  layout: "article",
  intro: [
    "Each bar is the average difference between twins, each dot one pair. Right of zero means Smart Lanes did better.",
  ],
  chapters: [
    {
      id: "method",
      title: "Twins on one map",
      summary: "Each junction is built twice side by side, once left to the game and once for Smart Lanes, and both run at the same time.",
      blocks: [
        {
          type: "steps",
          steps: [
            { title: "Twins", text: "The Stress Test builds every test junction as twins with identical parameters, each in a zone Smart Lanes reads: `game` (left as built), `sl` (smart lanes), and measuring modes." },
            { title: "Own towns", text: "Each twin is fed by its own towns of about 400 people, linked so that no lane change is forced inside the zone." },
            { title: "Record", text: "After a 3-minute warm-up the traffic log samples every zone every 10 game seconds for 20 game minutes, at 2x speed." },
            { title: "Check", text: "Each twin must have got its mode (Smart Lanes wrote it, or left it alone, lights off or kept); a pair that did not is left out." },
            { title: "Compare", text: "Pair by pair: speed, the share of cars standing, queues and cars through per minute; wins and losses with a sign test, Holm-adjusted over the sheet." },
          ],
        },
        {
          type: "facts",
          facts: [
            { label: "pairs won against the game's lanes", value: "46 of 48", note: "the pairs listed in the mod's description" },
            { label: "speed at slip-lane junctions", value: "3x", note: "13 to 42 km/h on the Channelized T" },
            { label: "more cars through 2-lane roundabouts", value: "+27 %", note: "60 to 76 cars a minute" },
            { label: "game minutes per run", value: "20", note: "sampled every 10 s after the warm-up" },
          ],
        },
        {
          type: "p",
          text: "Speed is measured in the junction and its approaches; \"standing\" is the share of cars stopped. With only a few pairs a result is a first look, not a verdict.",
        },
        { type: "sources", items: ["plans/square_stress_test/BENCH.md, SHOWCASE.md, FLOW.md", "RESULTS.md · header", "mods/square_smart_lanes/_metadata/description.html · Tested against the game's lanes"] },
      ],
    },
    {
      id: "overview",
      title: "Smart Lanes against the game's lanes",
      summary: "Bench sheets 1 to 3, one row per junction type: the bar is the mean difference, each dot one pair.",
      blocks: [
        {
          type: "deltas",
          title: "Speed, Smart Lanes minus game lanes",
          table: { file: PAIRS, value: "d_kmh", groupBy: GROUP, only: MAIN, labels: MAIN_LABELS },
          unit: " km/h",
          labels: { better: "Faster", worse: "Slower" },
          rowHeader: "Junction",
          footer: "Each dot is one pair of twins; the number after the bar is the mean and how many pairs Smart Lanes won.",
        },
        {
          type: "deltas",
          title: "Cars through per minute, Smart Lanes minus game lanes",
          table: { file: PAIRS, value: "d_thru", groupBy: GROUP, only: MAIN, labels: MAIN_LABELS },
          unit: "/min",
          labels: { better: "More cars", worse: "Fewer cars" },
          rowHeader: "Junction",
        },
        {
          type: "p",
          text: "At the lane drop the game's own connections already equal Smart Lanes' rule (its twins logged `same`, nothing written), so both twins had the same lanes and the 5 of 6 is noise. At the diamond, speed rose but throughput did not: the ramps were never the bottleneck.",
        },
        { type: "sources", items: ["RESULTS.md · Verdicts, Bench sheets s1-s3", "data: bench-pairs.json"] },
      ],
    },
    {
      id: "slip-lanes",
      title: "Slip lanes: the lights were the whole difference",
      summary: "Sheet 2's third twin kept Smart Lanes' lanes but the game's lights, and was as slow as the game.",
      blocks: [
        {
          type: "compare",
          before: { src: `${BENCH}/2026-10-13_0610_s2/shots/g1b.jpg`, label: "Game lanes" },
          after: { src: `${BENCH}/2026-10-13_0610_s2/shots/g1a.jpg`, label: "Smart Lanes" },
          caption: "The same Channelized T at the end of the record: the game's twin (left) queues at the lights it put on the slip-lane junctions; Smart Lanes' twin (right) flows.",
        },
        {
          type: "deltas",
          title: "Channelized T, speed: what made it faster",
          table: {
            file: PAIRS,
            value: "d_kmh",
            groupBy: GROUP,
            only: [`Sheet 2 | cht | ${VS}`, "Sheet 2 | cht | Smart Lanes vs Smart Lanes, game's lights"],
            labels: { [`Sheet 2 | cht | ${VS}`]: "Smart Lanes vs game lanes", "Sheet 2 | cht | Smart Lanes vs Smart Lanes, game's lights": "Smart Lanes vs Smart Lanes with the game's lights" },
          },
          unit: " km/h",
          labels: { better: "Faster", worse: "Slower" },
          rowHeader: "Comparison",
        },
        {
          type: "p",
          text: "The game lit every slip-lane junction of the test (81 lights kept in the keep-lights twins), so traffic stopped where it should only merge. Switching them off (\"No lights at roundabouts and ramps\") is worth +29 km/h on its own and +17 cars a minute, 9 of 9 pairs.",
        },
        { type: "sources", items: ["RESULTS.md · Verdicts (bench s2)", "Bench runs · Sheet 2"] },
      ],
    },
    {
      id: "crossroads",
      title: "Crossroads and T-junctions",
      summary: "Faster at lit T-junctions and crossroads with the game's own phases, after the test rig itself was fixed.",
      blocks: [
        {
          type: "compare",
          before: { src: `${BENCH}/2026-10-13_0733_s3/shots/g1b.jpg`, label: "Game lanes" },
          after: { src: `${BENCH}/2026-10-13_0733_s3/shots/g1a.jpg`, label: "Smart Lanes" },
          caption: "A lit 2x2 T-junction of sheet 3 (set 1, 18.9 against 39.1 km/h).",
        },
        {
          type: "deltas",
          title: "Lights showcase, Smart Lanes minus game lanes per run",
          table: {
            file: SHOW,
            value: "d_kmh",
            groupBy: ["run", "compare"],
            only: [`Run 3 | ${VS}`, `Run 4 | ${VS}`, `Run 5 | ${VS}`, `Run 6 | ${VS}`],
            labels: { [`Run 3 | ${VS}`]: "Run 3 (jammed, old rig joins)", [`Run 4 | ${VS}`]: "Run 4 (jammed, old rig joins)", [`Run 5 | ${VS}`]: "Run 5 (rig fixed, ~400 people)", [`Run 6 | ${VS}`]: "Run 6 (light traffic)" },
          },
          unit: " km/h",
          labels: { better: "Faster", worse: "Slower" },
          rowHeader: "Run",
          footer: "Re-read from the logs with today's flow report, so numbers can differ slightly from the ones recorded at the time.",
        },
        {
          type: "p",
          text: "Runs 3 and 4 had Smart Lanes slower at 2x2 crossroads. The rig joined the arms to the link roads lane to lane only, forcing lane changes that hurt a layout pinning each turn to one exit lane, and the towns were three to ten times the size. Run 5 fixed both and the sign flipped: +3.5 km/h, 11 of 12 pairs (p = 0.006), the largest gain at 3x3 crossroads. Sheet 3 then settled the T: +9.2 km/h, 9 of 9.",
        },
        { type: "sources", items: ["RESULTS.md · Verdicts, Runs 3-6, Bench sheet s3", "data: showcase-pairs.json"] },
      ],
    },
    {
      id: "roundabouts",
      title: "Roundabouts",
      summary: "Two-lane roundabouts carry more cars; wider rings and small town rings each needed their own layout (Behind the scenes).",
      blocks: [
        {
          type: "compare",
          before: { src: `${BENCH}/2026-10-13_0610_s1/shots/g1b.jpg`, label: "Game lanes" },
          after: { src: `${BENCH}/2026-10-13_0610_s1/shots/g1a.jpg`, label: "Smart Lanes" },
          caption: "A 2-lane, 4-arm roundabout of sheet 1 (set 1: 59.8 against 75.2 cars a minute).",
        },
        {
          type: "deltas",
          title: "2-lane roundabout, sheet 1: Smart Lanes minus the other twin",
          table: {
            file: PAIRS,
            value: "d_thru",
            groupBy: GROUP,
            only: [`Sheet 1 | rb4 | ${VS}`, "Sheet 1 | rb4 | Smart Lanes vs Smart Lanes, game's lights"],
            labels: { [`Sheet 1 | rb4 | ${VS}`]: "vs game lanes", "Sheet 1 | rb4 | Smart Lanes vs Smart Lanes, game's lights": "vs Smart Lanes with the game's lights" },
          },
          unit: "/min",
          labels: { better: "More cars", worse: "Fewer cars" },
          rowHeader: "Comparison",
        },
        {
          type: "p",
          text: "+16 cars a minute in 9 of 9 pairs, with the lights making no measurable difference at 2-lane roundabouts (unlike slip lanes). The micro benches then raced 3- and 4-lane rings, and Sheet 4 the small town roundabout (Behind the scenes, and the Showcase sliders).",
        },
        { type: "sources", items: ["RESULTS.md · Verdicts (bench s1)", "Behind the scenes · The hunt for a faster roundabout"] },
      ],
    },
    {
      id: "no-gain",
      title: "What did not help",
      summary: "Planned light phases, fanning every lane into every lane, fanning turns over the exit lanes and freeing the curb turn.",
      blocks: [
        {
          type: "deltas",
          title: "Measuring modes on the Lights showcase, speed",
          table: {
            file: SHOW,
            value: "d_kmh",
            groupBy: ["compare"],
            only: ["Smart Lanes phases vs Game lanes", "Full fan vs Game lanes", "Exit-lane fan vs Smart Lanes", "Smart Lanes vs Smart Lanes, curb turn locked"],
            labels: {
              "Smart Lanes phases vs Game lanes": "Smart Lanes phases vs game (runs 3, 4)",
              "Full fan vs Game lanes": "Full fan vs game (run 3)",
              "Exit-lane fan vs Smart Lanes": "Exit-lane fan vs Smart Lanes (run 6)",
              "Smart Lanes vs Smart Lanes, curb turn locked": "Free curb turn vs locked (run 4, jammed)",
            },
          },
          unit: " km/h",
          labels: { better: "Faster", worse: "Slower" },
          rowHeader: "Comparison",
        },
        {
          type: "deltas",
          title: "Free curb turn on sheet 3 (light traffic), speed",
          table: {
            file: PAIRS,
            value: "d_kmh",
            groupBy: GROUP,
            only: ["Sheet 3 | lt22 | Smart Lanes vs Smart Lanes, curb turn locked", "Sheet 3 | lx | Smart Lanes vs Smart Lanes, curb turn locked"],
            labels: { "Sheet 3 | lt22 | Smart Lanes vs Smart Lanes, curb turn locked": "Lit T-junction", "Sheet 3 | lx | Smart Lanes vs Smart Lanes, curb turn locked": "Lit crossroads" },
          },
          unit: " km/h",
          labels: { better: "Faster", worse: "Slower" },
          rowHeader: "Junction",
        },
        {
          type: "list",
          items: [
            "**Smart Lanes phases**: every set of every run slower (−4.7 to −4.8 km/h, about +24 points standing). Split cycles gave each approach ~21 s of 92 s, the game ~24 s of 71 s. It stays an option, off by default.",
            "**Full fan** (every lane to every lane, one phase per approach): the worst, dropped from the showcase.",
            "**Exit-lane fan** (turns may enter every exit lane): lost all 5 pairs against today's pinned lanes, so it never became the default; two turns sharing a lane in one phase merge without giving way.",
            "**Free curb turn**: no clear effect either way (7 of 12 pairs pooled); kept because it is harmless, and since revision 8 only on turn-only lanes.",
          ],
        },
        { type: "sources", items: ["RESULTS.md · Verdicts, Runs 1-6, Bench sheet s3", "PHASES_PLAN.md"] },
      ],
    },
  ],
};
