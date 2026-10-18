// Smart Lanes: the visual tour (generic story kind, article layout, image blocks first). The before / after pairs and
// their speeds come from plans/square_smart_lanes/site/showcase.json (build_data.py: every bench set shot as both game
// lanes and Smart Lanes, numbers from the game logs); only the plain names and notes live here.
import type { Block, StoryPair, StorySource } from "../../components/sections/story/types.ts";
import data from "../../../../plans/square_smart_lanes/site/showcase.json" with { type: "json" };

const SHOTS = "plans/square_smart_lanes/shots";
const PLAY = "plans/square_smart_lanes/site/shots";

interface ShowPair {
  bench: string; page: string; test: string; before: string; after: string;
  kmhGame: number | null; kmhSmart: number | null; thruGame: number | null; thruSmart: number | null;
}
const pairs = (data as { version: number; pairs: ShowPair[] }).pairs;
if ((data as { version: number }).version !== 1) throw new Error("showcase.json: unknown version (rerun plans/square_smart_lanes/site/build_data.py)");

/** Plain names of the bench tests (build_data.py TESTS has the full ones). */
const NAME: Record<string, string> = {
  rb4: "Two-lane roundabout",
  drop: "Lane drop, 3 to 2 lanes",
  cht: "T-junction with slip lanes",
  dia: "Diamond interchange",
  lt22: "T-junction with lights",
  lx: "Crossroads with lights",
  rb2t: "Small town roundabout",
  rb2tm: "Small town roundabout",
  rb3m: "Three-lane roundabout",
  rb4lm: "Four-lane roundabout",
  rb2v: "Small town roundabout",
  rb3v: "Three-lane roundabout",
  rb4v: "Four-lane roundabout",
};
/** A short line after the numbers, keyed by bench page and test. */
const NOTE: Record<string, string> = {
  "2026-10-13_0610_s1|drop": "The game's lanes were already right here.",
  "2026-10-13_0610_s2|cht": "The game's lights on the slip lanes were the whole difference.",
  "2026-10-13_2341_s4|rb2t": "A tie: matched lanes alone don't help a small ring.",
  "2026-10-14_0027_s4|rb2tm": "Lost to the game here; a test layout with lane changes between the arms ran 12.4.",
  "2026-10-14_0133_s4|rb2tm": "Faster this time, on a ring with nodes between the arms.",
  "2026-10-14_0133_s4|rb3m": "Lost on a 3-lane ring with nodes between the arms; wide rings now stay plain, with turbo lanes.",
  "2026-10-14_0201_s4|rb4v": "Turbo lanes on a plain four-lane ring.",
};

const n = (v: number | null) => (v == null ? "?" : v.toFixed(1));
const pair = (p: ShowPair): StoryPair => ({
  before: { src: p.before, label: "Game lanes" },
  after: { src: p.after, label: "Smart Lanes" },
  caption: `**${NAME[p.test] ?? p.test}** (${p.bench}): Smart Lanes ${n(p.kmhSmart)} km/h, game lanes ${n(p.kmhGame)}. ${NOTE[`${p.page}|${p.test}`] ?? ""}`.trim(),
});
const sheets = (keep: (p: ShowPair) => boolean): Block => ({ type: "pairs", pairs: pairs.filter(keep).map(pair) });

export const showcase: StorySource = {
  layout: "article",
  intro: [
    "Every junction here was built twice on the same map: once left to the game, once with Smart Lanes. Drag the line to compare the twins after 20 minutes of traffic. Click any picture in the walls to see it large.",
  ],
  chapters: [
    {
      id: "junctions",
      title: "Twins: game lanes against Smart Lanes",
      summary: "Slip lanes, an interchange, lit T-junctions and crossroads, a two-lane roundabout and a lane drop.",
      blocks: [sheets((p) => !p.page.endsWith("_s4"))],
    },
    {
      id: "roundabouts",
      title: "Roundabouts, round by round",
      summary: "Small town rings and wide rings needed different answers. Each round below changed the next.",
      blocks: [
        sheets((p) => p.page.endsWith("_s4")),
        {
          type: "compare",
          before: { src: "plans/square_smart_lanes/site/bench/2026-10-14_0201_s4/shots/s4g1b.jpg", label: "Game lanes" },
          after: { src: "plans/square_smart_lanes/site/bench/2026-10-14_0201_s4/shots/s4g1t.jpg", label: "Lane changes between arms" },
          caption: "The layout that shipped for small rings: cars change lanes on a node between the arms. 12.4 km/h against 8.0 for the game's lanes.",
        },
      ],
    },
    {
      id: "lane-view",
      title: "The lane view",
      summary: "The Smart Lanes tool draws every lane connection: teal goes in, orange comes out.",
      blocks: [
        {
          type: "mosaic",
          size: "m",
          images: [
            { src: `${SHOTS}/01-ring-lanes.jpg`, caption: "Chained roundabouts in the lane view" },
            { src: `${SHOTS}/18-ring-mid-nodes.jpg`, caption: "Lane changes (orange) between a roundabout's arms" },
            { src: `${SHOTS}/03-junction-hover.jpg`, caption: "Each entry lane its own ring lane" },
            { src: `${SHOTS}/02-ring-select.jpg`, caption: "A whole roundabout selected" },
            { src: `${PLAY}/2026-10-12-ring-arm-lanes.jpg`, caption: "Entries (teal) and exits (orange), lane by lane" },
            { src: `${PLAY}/2026-10-11-splitter-ring-lanes.jpg`, caption: "A roundabout with splitter islands" },
            { src: `${PLAY}/2026-10-11-hamburger-ring-lanes.jpg`, caption: "A hamburger roundabout" },
            { src: `${PLAY}/2026-10-11-oval-ring-lanes.jpg`, caption: "An oval roundabout" },
            { src: `${PLAY}/2026-10-11-channelized-x-lanes.jpg`, caption: "A channelized junction" },
            { src: `${PLAY}/2026-10-11-channelized-x-closeup.jpg`, caption: "Slip lanes close up" },
            { src: `${PLAY}/2026-10-11-parclo-lanes.jpg`, caption: "A parclo's ramps" },
            { src: `${PLAY}/2026-10-11-roundabout-interchange-lanes.jpg`, caption: "A roundabout interchange" },
            { src: `${PLAY}/2026-10-11-ramp-junction-lanes.jpg`, caption: "A ramp meeting a divided road" },
            { src: `${PLAY}/2026-10-14-t-junction-bus-turn.jpg`, caption: "A T-junction's lanes" },
          ],
        },
      ],
    },
    {
      id: "big-selections",
      title: "Whole districts at once",
      summary: "Shift+click picks up to 60 junctions; Apply sets them all.",
      blocks: [
        {
          type: "mosaic",
          size: "l",
          images: [
            { src: `${SHOTS}/16-district-select.jpg`, caption: "A district's junctions selected" },
            { src: `${SHOTS}/12-multi-select.jpg`, caption: "Many junctions of a city at once" },
            { src: `${SHOTS}/17-district-panel.jpg`, caption: "The panel: 50 junctions, smart lanes on 38" },
          ],
        },
      ],
    },
    {
      id: "lights",
      title: "Traffic lights",
      summary: "No lights where traffic should only merge; lights kept where movements cross.",
      blocks: [
        {
          type: "mosaic",
          size: "m",
          images: [
            { src: `${PLAY}/2026-10-12-phase-arrows.jpg`, caption: "One light phase: red and green arrows" },
            { src: `${PLAY}/2026-10-12-lit-crossroads-queue.jpg`, caption: "Queues at a lit crossroads" },
            { src: `${SHOTS}/07-crossing-phases.jpg`, caption: "A lit crossroads and the Crossing window" },
            { src: `${PLAY}/2026-10-12-crossing-phases.jpg`, caption: "Light phases in the Crossing window" },
            { src: `${PLAY}/2026-10-12-slip-junction-lights.jpg`, caption: "The game's light on a slip lane" },
          ],
        },
      ],
    },
    {
      id: "test-maps",
      title: "The test maps",
      summary: "Purpose-built maps: every junction twice, each fed by its own small towns.",
      blocks: [
        {
          type: "mosaic",
          size: "m",
          images: [
            { src: `${SHOTS}/10-bench-map.jpg`, caption: "A whole bench map of twin junctions" },
            { src: `${SHOTS}/05-showcase-map.jpg`, caption: "A lights test map" },
            { src: `${SHOTS}/08-bench-group.jpg`, caption: "One junction and its towns" },
            { src: `${SHOTS}/15-micro-rings.jpg`, caption: "Test towns linked by roundabouts" },
            { src: `${SHOTS}/11-grid-town.jpg`, caption: "A grid town of a test map" },
            { src: `${SHOTS}/09-roundabout-top.jpg`, caption: "A two-lane roundabout during a run" },
            { src: `${SHOTS}/06-roundabout-queue.jpg`, caption: "A roundabout under load" },
            { src: `${SHOTS}/04-busy-road.jpg`, caption: "Rush hour on a link road" },
          ],
        },
      ],
    },
  ],
};
