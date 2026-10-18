// Organic Towns: labels, sentences and metric rows of the map comparisons (generic kind "run-compare"; data written
// by plans/square_organic_towns/compare/build_compare.py, plain data). Texts are inline markup (**bold**, `code`),
// never HTML. Only erasable TypeScript: scripts/media.mjs imports mod.ts.
import type { CompareFacts, RawMetrics, RunCompareSource } from "../../components/sections/run-compare/types.ts";
import { fmt } from "../../lib/format.ts";

type X = Record<string, unknown>;
const list = (v: unknown): string[] => (Array.isArray(v) ? v.map(String) : []);
const code = (s: unknown) => "`" + String(s ?? "") + "`";
const sum = (d: CompareFacts, key: string, run: string) => d.summary[key]?.[run]?.sum ?? 0;
// the builder's medians as they are (no rounding), like its old generated notes
const median = (d: CompareFacts, key: string, run: string) => String(d.summary[key]?.[run]?.q?.[1] ?? "-");

export function otCompare(dir: string): RunCompareSource {
  return {
    dir,
    unit: { one: "town", many: "towns" },
    runKinds: { mod: { label: "mod" }, vanilla: { label: "vanilla", outline: true } },
    runCard: (r) => {
      const stop = String(r.stopLine ?? "").replace(/^\[SQOT_DEV\] /, "");
      return [
        `Log ${code(r.session)}, load ${r.load ?? ""}, ${r.loadAt || "-"}Z · ${r.kind === "mod" ? "Organic Towns on" : "Organic Towns off"}`,
        code(String(r.init || "-").slice(0, 120)),
        `SIMGROW ${r.simStart || "-"}-${r.simStop || "-"}Z: ${code(stop.slice(0, 160))}`,
      ];
    },
    describe: (d) =>
      d.single
        ? `Seed text ${d.seed} · one run · ${d.units} towns (SIMGROW) + ${d.extra[d.runs[0].id] ?? 0} created by the mod`
        : `Seed text ${d.seed} · ${d.runs.length} runs · ${d.units} towns paired by entity id${d.pairing === "id" ? "" : " (or position)"} with the first run`,
    autoNotes: (d) =>
      d.runs.map((r) =>
        `**${r.label}**: buildings ${fmt(sum(d, "buildingsStart", r.id))} -> ${fmt(sum(d, "buildingsEnd", r.id))}, ` +
        `persons ${fmt(sum(d, "personsEnd", r.id))}, pb (median) ${median(d, "pb", r.id)}, ` +
        `free lots ${median(d, "freeLotsPct", r.id)} %, street ${median(d, "streetPerPerson", r.id)} m per person.`),
    footer:
      "Images: in-game tour screenshots (the same camera per town), downscaled to JPEG. Metrics: dev mod `ALLTOWN` after " +
      "the simulation and `SIMGROW town` lines. Data: `data.json`. Built by `plans/square_organic_towns/compare/build_compare.py`.",
    summaryHint: {
      multi: "Median [quartiles] or sum over the paired towns. The last column is the ratio of the two runs picked as A and B (A / B).",
      single: "Median [quartiles] or sum over the towns the simulation grew (the mod-created districts and Works are listed separately).",
    },
    summaryRows: [
      { label: "Buildings start (sum)", key: "buildingsStart", mode: "sum" },
      { label: "Buildings after 40 y (sum)", key: "buildingsEnd", mode: "sum" },
      { label: "Buildings after 40 y (per town)", key: "buildingsEnd", mode: "q" },
      { label: "Persons after 40 y (sum)", key: "personsEnd", mode: "sum" },
      { label: "Persons per building (pb)", key: "pb", mode: "q", digits: 2 },
      { label: "Free lots (% of lots)", key: "freeLotsPct", mode: "q", digits: 1 },
      { label: "Radius r (m, 90 % of buildings)", key: "r", mode: "q" },
      { label: "r / sqrt(buildings)", key: "rPerSqrtB", mode: "q", digits: 1 },
      { label: "Buildings / ha (dens)", key: "dens", mode: "q", digits: 1 },
      { label: "Persons / ha (r disc)", key: "personsPerHa", mode: "q", digits: 1 },
      { label: "Spread ratio (1 = disc)", key: "spread", mode: "q", digits: 2 },
      { label: "Beyond 1.5 Req (% buildings)", key: "beyondPct", mode: "q", digits: 1 },
      { label: "Grid share (orient orth)", key: "orth", mode: "q", digits: 2 },
      { label: "Street edges (sum)", key: "edges", mode: "sum" },
      { label: "Street length (km, sum)", key: "streetLen", mode: "sum", digits: 1, scale: 1000 },
      { label: "Street m per person", key: "streetPerPerson", mode: "q", digits: 2 },
      { label: "Empty street length (km, sum)", key: "emptyLen", mode: "sum", digits: 1, scale: 1000 },
      { label: "Empty share of street length (%)", key: "emptyLenPct", mode: "q", digits: 1 },
      { label: "Dead ends (sum)", key: "deadEnds", mode: "sum" },
      { label: "Dead ends per km street", key: "deadEndsPerKm", mode: "q", digits: 2 },
      { label: "Mod-built share of the edges (%)", key: "modShare", mode: "q", digits: 1 },
      { label: "Residential level 2 share (% capacity)", key: "lvl2Pct", mode: "q" },
      { label: "Residential levels 3-4 share (% capacity)", key: "lvl34Pct", mode: "q" },
    ],
    unitRows: [
      { label: "Buildings start → end", ratioKey: "buildingsEnd", cell: (m) => `${fmt(m.buildingsStart)} → **${fmt(m.buildingsEnd)}**` },
      { label: "Persons start → end", ratioKey: "personsEnd", cell: (m) => `${fmt(m.personsStart)} → **${fmt(m.personsEnd)}**` },
      { label: "Persons per building", ratioKey: "pb", cell: (m) => fmt(m.pb, 2) },
      { label: "Free lots %", ratioKey: "freeLotsPct", cell: (m) => fmt(m.freeLotsPct, 0) },
      { label: "Radius r (m)", ratioKey: "r", cell: (m) => fmt(m.r) },
      { label: "Buildings / ha", ratioKey: "dens", cell: (m) => fmt(m.dens, 1) },
      { label: "Spread / beyond %", ratioKey: "spread", cell: (m) => `${fmt(m.spread, 2)} / ${fmt(m.beyondPct)}` },
      { label: "Street edges / length (km)", ratioKey: "streetLen", cell: (m) => `${fmt(m.edges)} / ${fmt(Number(m.streetLen) / 1000, 1)}` },
      { label: "Empty street (km, % length)", ratioKey: "emptyLen", cell: (m) => `${fmt(Number(m.emptyLen) / 1000, 1)} (${fmt(m.emptyLenPct, 0)} %)` },
      { label: "Dead ends", ratioKey: "deadEnds", cell: (m) => fmt(m.deadEnds) },
      { label: "Orient orth / radial / ring", cell: (m) => String(m.orient || "-") },
      { label: "Mod-built share of edges %", ratioKey: "modShare", cell: (m) => fmt(m.modShare, 0) },
      { label: "Industries in town / enclosed", cell: (m) => String(m.ind || "-") },
      { label: "Res. levels 1/2/3/4, actual %", cell: (m) => String(m.lvlActual || "-") },
      { label: "Form / shape", cell: (m) => `${m.form || "-"} / ${m.shape || "-"}` },
    ],
    unitNotes: (e: X, m: RawMetrics) => {
      const ex: string[] = [];
      if (e.satelliteBuilt) ex.push("satellite village built");
      if (list(e.districts).length) ex.push("district " + list(e.districts).join(", "));
      if (list(e.works).length) ex.push(list(e.works).join(", ") + (e.worksLinked ? " (linked)" : ""));
      if (list(e.bridges).length) ex.push("bridge " + list(e.bridges).join(", "));
      if (e.coastal) ex.push("coastal pick");
      if (e.character) ex.push("character town");
      if (e.levels) ex.push("level weights: " + e.levels);
      if (e.forestShareFirst != null) ex.push(`forest share ${e.forestShareFirst} → ${e.forestShareLast}`);
      if (e.matLast != null)
        ex.push(`last CHECK mat ${fmt(e.matLast, 2)} demK ${fmt(e.demKLast, 2)}` + (e.matHalfAt ? ` (mat 0.5 at ${e.matHalfAt} persons)` : ""));
      const why = (e.checkWhy ?? {}) as Record<string, number>;
      if (Object.keys(why).length)
        ex.push("CHECK " + Object.entries(why).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join(", "));
      if (e.levelsSkip) ex.push("LEVELS skip=" + e.levelsSkip);
      ex.push(`mod-built street edges ${e.builtEdges} of ${m.edges} in ${e.builds} builds`);
      return ex;
    },
    categories: {
      clear: { label: "Clearly different", tag: "clearly different (0119 pair)", tone: "run-0" },
      similar: { label: "Similar footprint", tag: "similar footprint (0119 pair)", tone: "muted" },
    },
    verdictLabel: "0119 verdict:",
    gallery: {
      hint: "Every town of the run after the simulation (the tour's shot, the same 1800 m camera). Pick a town for its full metrics below.",
      facts: (m, e) => [
        ["buildings", `${fmt(m.buildingsStart)} → ${fmt(m.buildingsEnd)}`],
        ["pb", fmt(m.pb, 2)],
        ["free", `${fmt(m.freeLotsPct, 0)} %`],
        ["spread", fmt(m.spread, 2)],
        ["mod edges", `${fmt(m.modShare, 0)} %`],
        ["r", `${fmt(m.r)} m`],
        ...(e && e.matLast != null ? ([["mat", fmt(e.matLast, 2)], ["demK", fmt(e.demKLast, 2)]] as [string, string][]) : []),
      ],
      flags: (m, e) => {
        const f: string[] = [];
        if (e) {
          const sat = Number(e.satellites) || 0;
          if (sat) f.push(sat > 1 ? `${sat} satellites` : "satellite");
          if (list(e.districts).length) f.push("district " + list(e.districts).join(", "));
          if (list(e.works).length) f.push(list(e.works).join(", "));
          if (list(e.bridges).length) f.push("bridge");
          if (e.coastal) f.push("coastal");
          if (e.character) f.push("character");
        }
        return [[m.form, m.shape, m.style].filter(Boolean).join(" / "), ...f].filter(Boolean).join(" · ");
      },
    },
    extras: {
      title: "Extra towns (districts and Works)",
      description:
        "Towns a mod run created (not in SIMGROW and not in the per-town numbers). Their shots are centered on the extra town and mostly show its parent next to it.",
      columns: [
        { label: "Buildings", key: "buildings" },
        { label: "Edges", key: "edges" },
        { label: "r (m)", key: "r" },
        { label: "pb", key: "pb", digits: 2 },
        { label: "Empty edges", key: "emptyEdges" },
      ],
      tag: "created",
      facts: (x) => [["buildings", fmt(x.buildings)], ["edges", fmt(x.edges)], ["pb", fmt(x.pb, 2)], ["r", `${fmt(x.r)} m`]],
    },
    listNote:
      "New comparison: `uv run plans/square_organic_towns/compare/build_compare.py --a <session>:1 --b <session>:2` (or `--single`, `--add`), then rebuild the site.",
  };
}
