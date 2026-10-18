// Roundabouts & Interchanges: the visual tour (generic story kind, article layout, image blocks first). Images: the
// release captures in plans/square_roundabouts/shots/ and the test-session screenshots in plans/square_roundabouts/site/
// shots/ (captions in build_data.py CURATED and site/shots/shots.json). Captions stay short and plain.
import type { StorySource } from "../../components/sections/story/types.ts";

const SHOTS = "plans/square_roundabouts/shots";
const PLAY = "plans/square_roundabouts/site/shots";

export const showcase: StorySource = {
  layout: "article",
  intro: ["Every picture here is from the game. Click any image to see it large; use ← and → to flip through."],
  chapters: [
    {
      id: "fields",
      title: "Whole fields of junctions",
      summary: "A test mod packs every setting of every menu entry onto one map. From high up it looks like a carpet.",
      blocks: [
        {
          type: "mosaic",
          size: "l",
          lead: true,
          preset: "default",
          images: [
            { src: `${SHOTS}/20-horizon-mix.jpg`, caption: "Every entry, all the way to the horizon" },
            { src: `${SHOTS}/18-planet-topdown.jpg`, caption: "The whole showcase disc from high above" },
            { src: `${SHOTS}/31-planet-roundabouts.jpg`, caption: "A disc of roundabouts" },
            { src: `${SHOTS}/27-planet-interchanges.jpg`, caption: "A disc of interchanges" },
            { src: `${SHOTS}/32-horizon-roundabouts.jpg`, caption: "Roundabouts to the horizon" },
            { src: `${SHOTS}/28-magic-field.jpg`, caption: "A field of Magic Roundabouts" },
            { src: `${PLAY}/2026-10-10-showcase-planet-mixed.jpg`, caption: "The first showcase map, from orbit" },
            { src: `${PLAY}/2026-10-10-showcase-horizon-mixed.jpg`, caption: "The first showcase map, to the horizon" },
            { src: `${PLAY}/2026-10-10-showcase-radial-grid.jpg`, caption: "One spoke per menu entry" },
          ],
        },
      ],
    },
    {
      id: "roundabouts",
      title: "Roundabouts",
      summary: "Round or oval, 10 to 60 meters, one to four ring lanes, three to six arms, with islands, trees, a fountain or a road straight through.",
      blocks: [
        {
          type: "mosaic",
          size: "m",
          images: [
            { src: `${SHOTS}/19-oblique-mix.jpg`, caption: "Ovals, chained rings, a channelized junction and interchanges" },
            { src: `${SHOTS}/01-overview.jpg`, caption: "A field of roundabout variants" },
            { src: `${SHOTS}/02-overview-variants.jpg`, caption: "Ovals, a Magic Roundabout and 4 to 6 arms" },
            { src: `${SHOTS}/04-top-down.jpg`, caption: "4 to 6 arms from above" },
            { src: `${SHOTS}/14-top-down-variety.jpg`, caption: "Planted islands, a hamburger and a channelized junction" },
            { src: `${SHOTS}/15-oblique-hamburger.jpg`, caption: "A road straight through the middle" },
            { src: `${SHOTS}/33-ovals-chains.jpg`, caption: "Ovals and chained rings" },
            { src: `${PLAY}/2026-10-10-showcase-roundabout-variety.jpg`, caption: "Roundabout variety" },
            { src: `${PLAY}/2026-10-11-oval-roundabout-lanes.jpg`, caption: "An oval with splitter islands" },
            { src: `${PLAY}/2026-10-11-hamburger-roundabout-lanes.jpg`, caption: "A hamburger roundabout" },
            { src: `${PLAY}/2026-10-12-three-arm-roundabout.jpg`, caption: "Three arms" },
            { src: `${PLAY}/2026-10-12-roundabout-oblique-skyline.jpg`, caption: "In front of a skyline" },
          ],
        },
      ],
    },
    {
      id: "magic",
      title: "The Magic Roundabout",
      summary: "Five little roundabouts on a two-way ring, like the famous one in Swindon.",
      blocks: [
        {
          type: "mosaic",
          size: "m",
          images: [
            { src: `${SHOTS}/03-magic-closeup.jpg`, caption: "Five minis on a two-way ring" },
            { src: `${SHOTS}/30-magic-trees.jpg`, caption: "With a tree island" },
            { src: `${SHOTS}/29-magic-islands.jpg`, caption: "Plain, trees, paved" },
            { src: `${PLAY}/2026-10-12-magic-roundabout-trees-traffic.jpg`, caption: "In traffic" },
            { src: `${PLAY}/2026-10-12-magic-roundabout-close-up.jpg`, caption: "Close up" },
          ],
        },
      ],
    },
    {
      id: "interchanges",
      title: "Junctions and interchanges",
      summary: "Slip-lane junctions, a roundabout over or under a highway, and parclo and diamond interchanges in three sizes.",
      blocks: [
        {
          type: "mosaic",
          size: "m",
          images: [
            { src: `${SHOTS}/24-interchange-grid.jpg`, caption: "Every highway interchange layout and size" },
            { src: `${SHOTS}/21-interchange-oblique.jpg`, caption: "A row of roundabout interchanges" },
            { src: `${SHOTS}/17-interchange-closeup.jpg`, caption: "A two-bridge roundabout interchange" },
            { src: `${SHOTS}/22-interchange-ring-closeup.jpg`, caption: "A ring bridge in a cutting" },
            { src: `${SHOTS}/23-dumbbell-magic-chain.jpg`, caption: "A dumbbell beside Magic Roundabouts" },
            { src: `${SHOTS}/25-parclo-diamond.jpg`, caption: "Parclo and diamond" },
            { src: `${SHOTS}/26-compact-interchanges.jpg`, caption: "Compact interchanges" },
            { src: `${PLAY}/2026-10-10-interchange-dumbbell-oblique.jpg`, caption: "A dumbbell interchange" },
            { src: `${PLAY}/2026-10-11-roundabout-interchange-top-down.jpg`, caption: "A roundabout interchange from above" },
            { src: `${PLAY}/2026-10-11-parclo-interchange-traffic.jpg`, caption: "A parclo in traffic" },
            { src: `${PLAY}/2026-10-11-channelized-junction-islands.jpg`, caption: "A channelized junction" },
          ],
        },
      ],
    },
    {
      id: "before-after",
      title: "Before and after",
      summary: "Drag the line to compare.",
      blocks: [
        {
          type: "pairs",
          pairs: [
            {
              before: { src: `${PLAY}/2026-10-13-bench-roundabout-single-lane.jpg`, label: "One lane" },
              after: { src: `${PLAY}/2026-10-13-bench-roundabout-two-lane.jpg`, label: "Two lanes" },
              caption: "The same crossing on the traffic test map with a one-lane and a two-lane ring.",
            },
            {
              before: { src: `${PLAY}/2026-10-12-three-arm-roundabout.jpg`, label: "Roundabout" },
              after: { src: `${PLAY}/2026-10-12-three-arm-roundabout-lanes-overlay.jpg`, label: "Its lanes" },
              caption: "A three-arm roundabout and the lanes Smart Lanes gives it.",
            },
            {
              before: { src: `${SHOTS}/06-settings-upper.jpg`, label: "Revision 1" },
              after: { src: `${PLAY}/settings-panel-roundabouts.jpg`, label: "Revision 6" },
              caption: "The settings: sliders in the menu at first, buttons in the side panel now.",
            },
            {
              before: { src: `${PLAY}/2026-10-13-bench-roundabout-compact-arrows.jpg`, label: "Compact" },
              after: { src: `${PLAY}/2026-10-13-bench-roundabout-large-ring.jpg`, label: "Large" },
              caption: "A compact and a large ring on the same crossing.",
            },
          ],
        },
      ],
    },
    {
      id: "traffic",
      title: "In traffic",
      summary: "Once placed, everything is ordinary road: cars, buses and trams use it like any other.",
      blocks: [
        {
          type: "mosaic",
          size: "m",
          images: [
            { src: `${PLAY}/2026-10-11-large-roundabout-traffic.jpg`, caption: "A large ring under load" },
            { src: `${PLAY}/2026-10-11-roundabout-interchange-traffic.jpg`, caption: "An interchange in traffic" },
            { src: `${PLAY}/2026-10-12-small-roundabout-traffic.jpg`, caption: "Queues at a small roundabout" },
            { src: `${PLAY}/2026-10-12-three-arm-roundabout-queue.jpg`, caption: "A three-arm ring queue" },
            { src: `${PLAY}/2026-10-12-three-arm-roundabout-traffic.jpg`, caption: "Three arms under load" },
            { src: `${PLAY}/2026-10-13-four-arm-roundabout-traffic.jpg`, caption: "Four arms with queues" },
            { src: `${PLAY}/2026-10-13-roundabout-conflict-points.jpg`, caption: "Where the ring's traffic meets" },
            { src: `${PLAY}/2026-10-13-four-arm-roundabout-arrows.jpg`, caption: "Ring direction" },
            { src: `${PLAY}/2026-10-11-two-lane-roundabout-lanes.jpg`, caption: "A two-lane ring's lanes" },
            { src: `${PLAY}/2026-10-11-four-arm-roundabout-lanes.jpg`, caption: "A four-arm ring's lanes" },
            { src: `${PLAY}/2026-10-12-roundabout-entry-lanes-close-up.jpg`, caption: "Entry lanes close up" },
            { src: `${PLAY}/2026-10-12-roundabout-arm-turns-close-up.jpg`, caption: "Turn paths at an arm" },
          ],
        },
      ],
    },
    {
      id: "menu",
      title: "In the menu",
      summary: "Seven entries next to the game's own roundabout and interchanges; the settings sit in the panel on the left.",
      blocks: [
        {
          type: "mosaic",
          size: "s",
          images: [
            { src: `${SHOTS}/08-menu-strip.jpg`, caption: "The mod's entries in the road menu" },
            { src: `${PLAY}/settings-panel-roundabouts.jpg`, caption: "Better Roundabouts settings" },
            { src: `${PLAY}/settings-panel-magic.jpg`, caption: "Magic Roundabout settings" },
            { src: `${PLAY}/settings-panel-parclo-two-quadrants.jpg`, caption: "Parclo settings" },
            { src: `${SHOTS}/09-menu-main-hover.jpg`, caption: "Better Roundabouts hover card" },
            { src: `${SHOTS}/11-menu-magic-hover.jpg`, caption: "Magic Roundabout hover card" },
            { src: `${SHOTS}/12-menu-channel-hover.jpg`, caption: "Channelized Junction hover card" },
            { src: `${SHOTS}/13-menu-interchange-hover.jpg`, caption: "Roundabout Interchange hover card" },
          ],
        },
      ],
    },
  ],
};
