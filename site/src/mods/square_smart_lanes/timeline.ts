// Smart Lanes: the build timeline (generic story kind, timeline layout) plus the mod's changelog, read from
// mods/square_smart_lanes/_metadata/description.html. Entries from plans/square_smart_lanes/PLAN.md, PHASE7.md,
// PHASES_PLAN.md, PERF_REVIEW.md, RESULTS.md, TESTING.md and plans/square_roundabouts/PHASE6.md.
import type { StorySource } from "../../components/sections/story/types.ts";

const SHOTS = "plans/square_smart_lanes/shots";
const PLAY = "plans/square_smart_lanes/site/shots";

export const timeline: StorySource = {
  layout: "timeline",
  intro: ["Phase entries come from the plan docs, bench entries from the results ledger; revision entries are the mod's own changelog, read from its mod.io description."],
  tags: [
    { key: "phase", label: "Build phase" },
    { key: "game", label: "In-game test" },
    { key: "bench", label: "Bench run" },
    { key: "perf", label: "Performance" },
  ],
  changelog: { tag: "revision" },
  chapters: [
    {
      id: "lane-probe",
      title: "A probe reads the vanilla roundabout's lanes",
      date: "2026-10-08",
      tags: ["phase", "game"],
      summary: "Roundabouts & Interchanges' Phase 6 probe found the engine already lets only the outer ring lane exit; lane discipline became a mod of its own.",
      blocks: [{ type: "sources", items: ["plans/square_roundabouts/PHASE6.md", "docs/findings/roads.md · Junction lane connections"] }],
    },
    {
      id: "phase-1",
      title: "Phase 1: automatic roundabouts",
      date: "2026-10-08",
      tags: ["phase"],
      summary: "A game script that finds one-way rings among the built nodes and writes matched lanes, with the engine-thread / GUI-thread split that every later feature reuses.",
      blocks: [{ type: "sources", items: ["PLAN.md · Phase 1"] }],
    },
    {
      id: "first-game-test",
      title: "First in-game round: the tool works, two crashes",
      date: "2026-10-08",
      tags: ["game"],
      summary: "Picking, ring selection and the lane view worked. The NodeViewer crashed on a plain ring node, and a remove-only Reset crashed the simulation 13 s later; Reset became a full write of the game's default model.",
      blocks: [{ type: "sources", items: ["PLAN.md · Phase 2 step 1 in-game results"] }],
    },
    {
      id: "phase-4",
      title: "Phase 4: slip-lane junctions and the lane status",
      date: "2026-10-08",
      tags: ["phase"],
      summary: "A Channelized Junction's slip nodes had the engine's crossing fan; slip lanes got matched lanes without crossings, and the tool a badge for what a junction has now.",
      blocks: [{ type: "sources", items: ["PLAN.md · Phase 4, Lane status badge", "TESTING.md · G, H"] }],
    },
    {
      id: "crossroads",
      title: "Crossroads, lights and the junction audit",
      date: "2026-10-11",
      tags: ["phase", "game"],
      summary: "Crossroads and T-junctions, \"No lights at roundabouts and ramps\", tangential ramps, the ramp's own lane, and the audit that logs avoidable inefficiencies. A crash from stale light phases led to the re-pointing of every phase.",
      blocks: [
        { type: "figure", src: `${PLAY}/2026-10-11-roundabout-interchange-lanes.jpg`, caption: "Roundabout Interchange ring and ramps in the lane view, 2026-10-11." },
        { type: "sources", items: ["TESTING.md · I, J, K, L, X", "PHASE7.md · Crash rules"] },
      ],
    },
    {
      id: "phase-7",
      title: "Phase 7: look-ahead, lane drops, streets, many junctions",
      date: "2026-10-11",
      tags: ["phase", "perf"],
      summary: "Each step in its own agent with a review: look-ahead for the own-lane merge, lane drops and gains, exit lanes before off-ramps, street and multi selection, the bench's skip summary, then a performance review (Shift+click into a 60-junction selection 12 ms to 0.6 ms).",
      blocks: [{ type: "sources", items: ["PHASE7.md", "PERF_REVIEW.md · 2026-10-11"] }],
    },
    {
      id: "curb-turn",
      title: "Free curb turn: turners never give way",
      date: "2026-10-12",
      tags: ["game", "phase"],
      summary: "Freed in every phase, curb turners drove into green traffic: TF3 has no permissive turn. The setting became Off / When safe / Always, and a probe measured the game's default phases (6 phases, ~71-78 s cycles).",
      blocks: [{ type: "sources", items: ["PLAN.md · Free curb turn, Revised 2026-10-12", "docs/findings/roads.md · A connection unlocked in a phase does not give way"] }],
    },
    {
      id: "frame-budget",
      title: "The automatic pass spread over frames",
      date: "2026-10-12",
      tags: ["perf"],
      summary: "The Lights showcase at 8x stuttered: 160-node jobs took 97 ms on average in one frame, 237 ms at worst. Cheaper lane writes and an 8 ms frame budget, with identical results.",
      blocks: [{ type: "sources", items: ["PERF_REVIEW.md · 2026-10-12", "session 2026-10-12_2129_top-up-530609"] }],
    },
    {
      id: "showcase-runs",
      title: "Lights showcase runs 1-6",
      date: "2026-10-13",
      tags: ["bench"],
      summary: "Twins of lit crossroads on one map. Smart Lanes phases and the full fan lost every set; after fixing the rig's lane joins and the jam, Smart Lanes' lanes won 11 of 12 pairs. The exit-lane fan lost all 5.",
      blocks: [{ type: "sources", items: ["RESULTS.md · Runs 1-6"] }],
    },
    {
      id: "bench-sheets",
      title: "Bench sheets 1-3",
      date: "2026-10-13",
      tags: ["bench"],
      summary: "Purpose-built sheets: 2-lane roundabouts +16 cars a minute (9 of 9), Channelized T +28.5 km/h (9 of 9, all of it from the lights), lit T +9.2 km/h (9 of 9).",
      blocks: [
        { type: "figure", src: `${SHOTS}/10-bench-map.jpg`, caption: "A bench map: twin junctions between their own towns." },
        { type: "sources", items: ["RESULTS.md · Bench sheets s1-s3"] },
      ],
    },
    {
      id: "micro-bench",
      title: "Micro benches: a loss that was a bug",
      date: "2026-10-13",
      tags: ["bench", "phase"],
      summary: "3-lane rings lost, 4-lane rings won; the twins had ended with different layouts by build order. Whole rings in the automatic pass fixed it, and six ring layouts raced on one map.",
      blocks: [{ type: "sources", items: ["RESULTS.md · Bench micro, micro v2", "PLAN.md · Ring layout variants, Whole rings"] }],
    },
    {
      id: "sheet-4",
      title: "Sheet 4: the small roundabout",
      date: "2026-10-14",
      tags: ["bench", "game"],
      summary: "Four runs on a 2-lane ring with town street arms: matched lanes no gain, spiral better, lane changes at mid nodes best (+47 % cars through). Mid nodes hurt 3- and 4-lane rings.",
      blocks: [{ type: "sources", items: ["RESULTS.md · Bench sheet s4 (four runs)"] }],
    },
    {
      id: "reset-sticks",
      title: "Reset sticks and open exits, tested in game",
      date: "2026-10-14",
      tags: ["game"],
      summary: "A bus stop moved on a reset junction's arm brought smart lanes back; buses made U-turns on short blocks. Both fixes passed their first in-game steps the same day.",
      blocks: [{ type: "sources", items: ["TESTING.md · RK, OE", "docs/findings/roads.md · Vehicles change lanes between junctions"] }],
    },
  ],
};
