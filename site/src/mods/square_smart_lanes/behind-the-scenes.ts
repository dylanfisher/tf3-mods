// Smart Lanes: how it was built, in one page (generic story kind, article layout). Short versions of the former "How
// it works", "Design decisions", "Problems solved", "Case study: the faster roundabout" and "Testing" pages. Facts from
// plans/square_smart_lanes/ (PLAN.md, PHASE7.md, RESULTS.md, TESTING.md, PERF_REVIEW.md) and docs/findings/roads.md;
// the chart reads its pairs from plans/square_smart_lanes/site/data/bench-pairs.json (build_data.py).
import type { StorySource } from "../../components/sections/story/types.ts";

const SHOTS = "plans/square_smart_lanes/shots";
const PLAY = "plans/square_smart_lanes/site/shots";
const PAIRS = "plans/square_smart_lanes/site/data/bench-pairs.json";
const V5 = (test: string, cmp: string) => `Sheet 4 v5 | ${test} | ${cmp}`;

export const behindTheScenes: StorySource = {
  layout: "article",
  intro: ["How the mod works and how it was made: the short version. The measured numbers are on the results, bench and data pages."],
  chapters: [
    {
      id: "how-it-works",
      title: "How it works",
      summary: "Smart Lanes writes the same lane settings you could make by hand with the game's Crossing Tool, right after you build.",
      blocks: [
        {
          type: "steps",
          steps: [
            { title: "You build", text: "A roundabout, a slip lane, a crossroads: the mod notes which junctions changed." },
            { title: "It reads", text: "Lanes from the road types, rings from their shape. Junctions you didn't touch are never read." },
            { title: "It plans", text: "Roundabouts first (the whole ring), then slip lanes, crossroads and lane drops." },
            { title: "It writes", text: "Lane connections and lights, a few milliseconds per frame so the game never stutters." },
          ],
        },
        {
          type: "list",
          items: [
            "**Roundabouts:** lanes line up one to one; the outer lane is exit-only when every exit has room. Small two-lane town rings get a node between the arms where cars change lanes.",
            "**Slip lanes and ramps:** lanes matched with no crossings; through traffic keeps its lanes.",
            "**Crossroads and T-junctions:** on wide roads the curb lane only turns, so turning cars never cut across.",
            "**Lights:** none where traffic should only give way or merge; kept where movements cross.",
            "**Bus and tram lanes** are left exactly as you set them.",
          ],
        },
        { type: "figure", src: `${SHOTS}/18-ring-mid-nodes.jpg`, caption: "Lane changes (orange) on the nodes between a roundabout's arms." },
      ],
    },
    {
      id: "decisions",
      title: "Choices we made",
      blocks: [
        {
          type: "list",
          items: [
            "**Write what the Crossing Tool writes** and nothing else, so removing the mod leaves ordinary junction settings.",
            "**Only what a build touched.** Junctions elsewhere are never changed.",
            "**One layout, no options:** one Apply button instead of a choice of lane styles.",
            "**Never squeeze lanes inside a junction**; lanes merge only where the road really narrows.",
            "**Lights off at roundabouts and ramps, kept at crossroads.**",
            "**Measure first:** every idea raced the game's lanes on a test map before it became a default.",
            "**Remember a Reset**, so a junction you set back to the game's lanes stays that way.",
          ],
        },
      ],
    },
    {
      id: "problems",
      title: "Problems solved",
      blocks: [
        {
          type: "list",
          items: [
            "**The lane view crashed the game** on a plain ring node. Fix: draw only what the node really has.",
            "**Reset deleted the junction's settings** and crashed the game later. Fix: Reset writes the game's default in full.",
            "**Four lanes turning into one** in the first ring rule. Fix: entry lane 1 joins ring lane 1, and so on.",
            "**Light phases pointing at old lanes** crashed the game. Fix: every write re-points the phases.",
            "**Stutter at 8x speed** on maps full of lit crossroads. Fix: the work is spread over frames, 8 ms at most each.",
            "**The same roundabout, different lanes** depending on build order. Fix: a touched ring is always planned whole.",
            "**A loss that was the test rig**: the test map's link roads forced lane changes. Fixed the rig, and the loss became a win.",
            "**Buses making U-turns** on short blocks. Fix: a turn into a road with a stop just ahead may use every lane.",
          ],
        },
        { type: "figure", src: `${PLAY}/2026-10-12-crossing-phases.jpg`, caption: "Light phases in the game's Crossing window." },
      ],
    },
    {
      id: "faster-roundabout",
      title: "The hunt for a faster roundabout",
      summary: "Six ring layouts raced on one map, and a lane change that works better on a node of its own than at a junction.",
      blocks: [
        {
          type: "deltas",
          title: "Speed against the game's lanes on a plain ring (sheet 4 v5)",
          table: {
            file: PAIRS,
            value: "d_kmh",
            groupBy: ["bench", "test", "compare"],
            only: [
              V5("rb2v", "Mid-node lane changes (mid-node ring) vs Game lanes (plain ring)"),
              V5("rb2v", "Smart Lanes (plain ring) vs Game lanes (plain ring)"),
              V5("rb3v", "Smart Lanes (plain ring) vs Game lanes (plain ring)"),
              V5("rb4v", "Smart Lanes (plain ring) vs Game lanes (plain ring)"),
              V5("rb4v", "Game lanes (mid-node ring) vs Game lanes (plain ring)"),
            ],
            labels: {
              [V5("rb2v", "Mid-node lane changes (mid-node ring) vs Game lanes (plain ring)")]: "2 lanes: lane changes between the arms",
              [V5("rb2v", "Smart Lanes (plain ring) vs Game lanes (plain ring)")]: "2 lanes: plain ring",
              [V5("rb3v", "Smart Lanes (plain ring) vs Game lanes (plain ring)")]: "3 lanes: turbo, plain ring",
              [V5("rb4v", "Smart Lanes (plain ring) vs Game lanes (plain ring)")]: "4 lanes: turbo, plain ring",
              [V5("rb4v", "Game lanes (mid-node ring) vs Game lanes (plain ring)")]: "4 lanes: game lanes with extra nodes",
            },
          },
          unit: " km/h",
          labels: { better: "Faster", worse: "Slower" },
          rowHeader: "Ring",
          footer: "One pair each, consistent with the earlier rounds on the two-lane ring.",
        },
        {
          type: "p",
          text: "Small two-lane rings ran fastest with lane changes on a node between the arms; wide rings with turbo lanes and no extra nodes. The game's menu removes those nodes on small rings, so Smart Lanes adds them itself.",
        },
      ],
    },
    {
      id: "testing",
      title: "Testing",
      blocks: [
        {
          type: "facts",
          facts: [
            { label: "offline tests", value: "600+" },
            { label: "crash rules, each from a real crash", value: "14" },
            { label: "in-game checklist sections", value: "50+" },
            { label: "test pairs won against the game", value: "46 of 48" },
          ],
        },
        {
          type: "list",
          items: [
            "**Offline tests** run the rules against a fake game, including mirrored worlds for left-hand traffic.",
            "**In-game rounds** for every feature, each answered from the mod's log lines.",
            "**Bench runs** on purpose-built maps: every junction twice, measured for 20 game minutes.",
          ],
        },
      ],
    },
  ],
};
