// Smart Lanes: labels, sentences and metric rows of the Stress Test bench runs (generic kind "run-compare"). Data:
// plans/square_smart_lanes/site/bench/<session>_<sheet>/data.json, written by plans/square_smart_lanes/site/build_data.py
// from the archived game logs (tools/bench_report.py + tools/flow_report.py, the numbers `make bench` prints). Texts are
// inline markup, never HTML. Only erasable TypeScript: scripts/media.mjs imports mod.ts.
import type { CompareFacts, RunCompareSource } from "../../components/sections/run-compare/types.ts";
import { fmt } from "../../lib/format.ts";

interface Comparison {
  test: string;
  title: string;
  a: string;
  b: string;
  pairs: number;
  wins: number;
  losses: number;
  dKmh: number | null;
  dThru: number | null;
  thruWins: number;
  p: number | null;
}

const signed = (v: number | null | undefined, d = 1) => (v == null ? "-" : `${v > 0 ? "+" : ""}${fmt(v, d)}`);
const comparisons = (d: CompareFacts): Comparison[] => (Array.isArray(d.notes.comparisons) ? (d.notes.comparisons as Comparison[]) : []);

export function benchSource(dir: string): RunCompareSource {
  return {
    dir,
    unit: { one: "set", many: "sets" },
    runName: { one: "twin", many: "twins" },
    runKinds: { game: { label: "game lanes", outline: true }, smart: { label: "Smart Lanes" } },
    runCard: (r) => [`Zone mode \`${String(r.mode ?? r.id)}\` · log \`${String(r.session ?? "")}\``],
    describe: (d) => {
      const n = d.notes;
      const parts = [`${d.runs.length} twins per set`, `${d.units} ${d.units === 1 ? "set" : "sets"}`];
      if (n.towns) parts.push(`${n.towns} towns of ~${n.pop ?? 400} people`);
      if (n.recordS) parts.push(`${Math.round(Number(n.recordS) / 60)} game minutes recorded`);
      if (!n.complete) parts.push("stopped early");
      return parts.join(" · ");
    },
    autoNotes: (d) => {
      const n = d.notes;
      const out = comparisons(d).map((c) => {
        const verdict = c.pairs >= 6 && c.p != null && c.p <= 0.05 ? " (significant)" : c.pairs >= 3 && (c.wins === c.pairs || c.losses === c.pairs) ? " (a trend)" : "";
        return `**${c.title}: ${c.a} vs ${c.b}**: ${signed(c.dKmh)} km/h, faster in ${c.wins} of ${c.pairs} ${c.pairs === 1 ? "pair" : "pairs"}` +
          (c.dThru != null ? `, ${signed(c.dThru)} cars a minute through` : "") + (c.pairs > 1 && c.p != null ? `, sign test p = ${fmt(c.p, 3)}` : "") + verdict + ".";
      });
      const setup = [`Settings in this run: Free curb turn \`${String(n.freeTurn ?? "-")}\``, `No lights at roundabouts and ramps \`${String(n.lights ?? "-")}\``, `Light phases \`${String(n.phases ?? "-")}\``];
      out.push(setup.join(", ") + (n.mapStanding != null ? `; map-wide ${fmt(n.mapStanding, 0)} % of cars standing (above ~45 % the map is saturated and speed mostly measures queues).` : "."));
      const ex = Array.isArray(n.excluded) ? n.excluded.length : 0;
      if (ex) out.push(`${ex} ${ex === 1 ? "pair was" : "pairs were"} left out of the comparisons (a twin that did not get its mode, or a mismatched zone).`);
      return out;
    },
    footer:
      "Images: the bench's own screenshot of each twin of the first set of every test, taken at the end of the record from the same height (sheets 1-3: the center of a higher view, cut out at the capture's resolution). " +
      "Metrics per twin over the record after a 3-minute warm-up: car-weighted mean speed in the junction zone, the share of cars under 0.5 m/s, " +
      "cars standing 5 s or longer (queue) and cars through per game minute. Data: `data.json`, built by `plans/square_smart_lanes/site/build_data.py` " +
      "from the archived game log (the same numbers as `make bench`).",
    summaryHint: {
      multi: "Median [quartiles] over the sets of this run. The last column is the ratio of the twins picked as A and B (A / B).",
      single: "Median [quartiles] over the sets.",
    },
    summaryRows: [
      { label: "Speed (km/h)", key: "kmh", mode: "q", digits: 1 },
      { label: "Cars through per minute", key: "thru", mode: "q", digits: 1 },
      { label: "Cars standing (%)", key: "standing", mode: "q", digits: 1 },
      { label: "Cars queued 5 s or longer", key: "queue", mode: "q", digits: 1 },
    ],
    unitRows: [
      { label: "Speed (km/h)", ratioKey: "kmh", cell: (m) => `**${fmt(m.kmh, 1)}**` },
      { label: "Cars through per minute", ratioKey: "thru", cell: (m) => fmt(m.thru, 1) },
      { label: "Cars standing (%)", ratioKey: "standing", cell: (m) => fmt(m.standing, 1) },
      { label: "Cars queued 5 s or longer", ratioKey: "queue", cell: (m) => fmt(m.queue, 1) },
      { label: "Samples", cell: (m) => fmt(m.samples) },
      { label: "Junction", cell: (m) => String(m.variant ?? "-") },
      { label: "Smart Lanes wrote / skipped", cell: (m) => `${fmt(m.applied)} / ${fmt(m.skipped)}` },
      { label: "Lights off / kept", cell: (m) => `${fmt(m.lightsOff)} / ${fmt(m.lightsKept)}` },
    ],
    unitNotes: (_x, m) => [`zone ${String(m.zone ?? "-")}`, ...(m.treatment ? [`treatment check failed: ${String(m.treatment)}`] : [])],
    categories: {
      faster: { label: "Smart Lanes faster", tag: "Smart Lanes faster than game lanes", tone: "run-0" },
      slower: { label: "Smart Lanes slower", tag: "Smart Lanes slower than game lanes", tone: "run-1" },
    },
    verdictLabel: "Smart Lanes vs game lanes:",
    listNote:
      "A new bench run: play a bench sheet in the Stress Test (Towns > Bench), then `uv run plans/square_smart_lanes/site/build_data.py` " +
      "(add the session to `BENCHES` there) and rebuild the site.",
  };
}
