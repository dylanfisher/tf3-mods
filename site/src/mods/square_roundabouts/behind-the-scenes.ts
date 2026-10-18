// Roundabouts & Interchanges: how it was built, in one page (generic story kind, article layout). Short versions of the
// former "How it works", "Design decisions", "Problems solved", "Case study: the negative zero" and "Testing" pages.
// Facts from plans/square_roundabouts/ (PLAN.md, INTERCHANGES.md, PROBE.md, TESTING.md, PHASE7_RUNBOOK.md,
// HISTORY.md), tests/square_roundabouts/ and docs/findings/roads.md.
import type { StorySource } from "../../components/sections/story/types.ts";

const SHOTS = "plans/square_roundabouts/shots";
const PLAY = "plans/square_roundabouts/site/shots";

export const behindTheScenes: StorySource = {
  layout: "article",
  intro: ["How the mod works and how it was made: the short version. Every probe run is on the data page."],
  chapters: [
    {
      id: "how-it-works",
      title: "How it works",
      summary: "The settings go in, a plan comes out, and the game is left with nothing but ordinary roads.",
      blocks: [
        {
          type: "steps",
          steps: [
            { title: "Settings", text: "Rows of buttons in the side panel while you place." },
            { title: "Plan", text: "Plain geometry code turns them into roads; it never looks at the map." },
            { title: "Grow", text: "The size is a minimum: if your roads don't fit, the ring takes the next size where they do." },
            { title: "Plain roads", text: "The game turns the build into streets you can edit, extend or bulldoze." },
          ],
        },
        {
          type: "facts",
          facts: [
            { label: "menu entries", value: "7" },
            { label: "times the game was asked what places", value: "≈44,000" },
            { label: "offline tests", value: "320" },
            { label: "scripts running while you play", value: "0" },
          ],
        },
        { type: "figure", src: `${SHOTS}/19-oblique-mix.jpg`, caption: "Ovals, chained rings, a channelized junction and interchanges, all from the menu." },
      ],
    },
    {
      id: "decisions",
      title: "Choices we made",
      summary: "Each one has a reason and a cost.",
      blocks: [
        {
          type: "list",
          items: [
            "**Ordinary roads, not a locked construction.** You can edit every piece afterwards; to change the settings you bulldoze and place again.",
            "**Only the game's own roads.** Nothing to break on game updates; the cost is no 3-lane ring and no turbo roundabout.",
            "**No greyed-out settings.** Every value builds something, so nothing is ever hidden or disabled.",
            "**The size is a minimum.** One growth rule instead of a list of limits per feature.",
            "**The Magic Roundabout is its own entry**, because none of the ring settings apply to it.",
            "**A tram line only straight through the middle.** A tram track joining the ring crashed the game.",
            "**Ask the game, then remember the answers.** A test mod asked the game's placement check tens of thousands of times; the answers became a table in the mod.",
            "**Lane rules became their own mod**, Smart Lanes, because a construction can't set lanes on roads it has already handed over.",
            "**One quadrant, mirrored.** Every highway interchange is built from one corner and mirrored to the others.",
            "**Buttons instead of sliders**, in the side panel instead of under the menu's tooltip.",
            "**Long ramps are capped** at about 480 m from the center instead of being refused.",
          ],
        },
      ],
    },
    {
      id: "problems",
      title: "Problems solved",
      summary: "What went wrong in game, and the fix.",
      blocks: [
        {
          type: "list",
          items: [
            "**Settings that greyed out and never came back** until the menu reopened. Fix: no conditional settings at all.",
            "**A tram line through the center crashed the game.** Fix: short tram-road stubs join the ring, the track runs between them.",
            "**Builds refused with nothing in the log**: junctions were eating whole road pieces. Fix: a model of how the game cuts junctions, fitted to its own verdicts.",
            "**Rings that failed at one size and placed at the next.** Fix: the exact sizes the game accepts, in a table.",
            "**Slip lanes refused at 40°.** Fix: a table of slip angles per road combination (50°, 65° or 80°).",
            "**Four-lane interchange rings refused.** Fix: the ring grows on wide highways.",
            "**Refused at 0°, placed at 350°**: a negative zero (below).",
            "**Small one-lane ovals with wide arms** were refused on a live map. Fix: they grow a step or three until the arms fit.",
          ],
        },
        { type: "figure", src: `${PLAY}/2026-10-11-channelized-junction-islands.jpg`, caption: "A channelized junction: the slip-lane angles came from the probe." },
      ],
    },
    {
      id: "negative-zero",
      title: "The negative zero",
      summary: "A parclo interchange was refused at exactly 0° rotation and placed at any other angle. Thirteen rounds of hunting later: one sign bit.",
      blocks: [
        {
          type: "table",
          head: ["", "South-east on-ramp", "North-west on-ramp"],
          rows: [
            ["Tangent", "`(+x, -0, -0)`", "`(-x, +0, -0)`"],
            ["At 0°", "`(-0)(+x) + (-0)` = **-0**", "`(-0)(-x) + 0` = +0"],
            ["Result", "refused", "placed"],
          ],
          caption: "Mirroring left a -0 in one ramp's direction, and the game refuses that at 0°. The fix turns every zero into +0.",
        },
        { type: "p", text: "The test mod never saw it, because it built its transform with +0. What found it: switching parts of the layout off in the real menu, half at a time, then comparing every number down to the sign of zero." },
        { type: "figure", src: `${SHOTS}/24-interchange-grid.jpg`, caption: "Every highway interchange layout and size, placed after the fix." },
      ],
    },
    {
      id: "testing",
      title: "Testing",
      summary: "Three layers: offline tests, the game's own placement check, and rounds in the game.",
      blocks: [
        {
          type: "list",
          items: [
            "**Offline tests** run the geometry without the game and sweep every setting; recorded fingerprints catch any layout that changes by accident.",
            "**The probe** (a test mod) places combinations in the game and logs which ones the game accepts; its tables are on the data page.",
            "**In-game rounds**: every revision was placed by hand from the menu, the only place some refusals show.",
            "**The Stress Test bench** builds the same crossing with different roundabouts and measures the traffic.",
            "**Fast:** building a layout takes about a millisecond, and nothing runs while you play.",
          ],
        },
      ],
    },
  ],
};
