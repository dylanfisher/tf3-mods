// Smart Lanes: result tables for the generic "data-explorer" kind. Data: plans/square_smart_lanes/site/data/*.json
// (plans/square_smart_lanes/site/build_data.py, from the archived game logs and .cache/test_timings.json). Labels and
// sentences live here, never in the data.
import type { ColumnLabel, DataExplorerSource } from "../../components/sections/data-explorer/types.ts";

const TESTS = {
  rb4: "Roundabout, 2 lanes, 4 arms",
  drop: "Lane drop 3 to 2",
  cht: "Channelized T (slip lanes)",
  dia: "Diamond interchange",
  lt22: "Lit T-junction 2x2",
  lx: "Lit crossroads",
  rb4l: "Roundabout, 4 lanes",
  rb3: "Roundabout, 3 lanes",
  rb2: "Roundabout, 2 lanes",
  rb2t: "2-lane ring, town arms",
  rb2tm: "2-lane ring, town arms, mid nodes",
  rb3m: "3-lane ring, mid nodes",
  rb4lm: "4-lane ring, mid nodes",
  rb2v: "2-lane ring: plain / mid nodes",
  rb3v: "3-lane ring: plain / mid nodes",
  rb4v: "4-lane ring: plain / mid nodes",
};
const SHAPES = {
  "2x2_X": "2x2 crossroads", "3x3_X": "3x3 crossroads", "3x2_X": "3x2 crossroads", T_2x2: "T 2x2", RB4_2L: "2-lane ring",
  "Lane_drop_3-2": "3 to 2 lanes", Channel_T: "Channelized T", Diamond_S: "Diamond, small", "RB_4-lane": "4-lane ring",
  "RB_3-lane": "3-lane ring", "RB_2-lane": "2-lane ring", RB_2L_town: "2-lane ring, town arms", RB_2L_town_mid: "2-lane ring, town arms, mid nodes",
  "RB_3-lane_mid": "3-lane ring, mid nodes", "RB_4-lane_mid": "4-lane ring, mid nodes",
};
const MODES = {
  game: "Game lanes", sl: "Smart Lanes", sl_keeplights: "Smart Lanes, game's lights", sl_lock: "Smart Lanes, curb turn locked",
  sl_rturbo: "Turbo", sl_rmatch: "Matched lanes", sl_rout1: "Outer lane exits only", sl_r2exit: "Two outer lanes exit",
  sl_rspiral: "Spiral", sl_rspread: "Turbo plus center lanes", sl_rsplit: "Split spiral", sl_rmid: "Mid-node lane changes",
  "game@plain": "Game lanes (plain ring)", "game@mid": "Game lanes (mid-node ring)", "sl@plain": "Smart Lanes (plain ring)",
  "sl_rsplit@mid": "Split spiral (mid-node ring)", "sl_rmid@mid": "Mid-node lane changes (mid-node ring)",
};
const FINDINGS = {
  squeeze: "Squeeze (lanes into one)", shared: "Shared exit lane", across: "Across the median", ramp_ramp: "Ramp onto ramp",
  u_turn: "U-turn", unfed: "Unfed lane", dead: "Dead lane", bypassed_turn: "Turn a slip lane serves", weave: "Weave within 80 m",
  lights: "Light left on", bad: "Bad connection", "-": "None",
};
const SECTIONS = {
  gui_update: "GUI frame (whole)", job: "Automatic job (one frame, before rev 4)", job_step: "Job step (one frame)",
  job_write: "Lane writes", job_classify: "Classify junctions", job_ring: "Ring search and plans", job_audit: "Junction audit",
  verify: "Verify re-read", resolve: "Tool: resolve target", hover: "Tool: hover", select: "Tool: select", refresh: "Tool: refresh",
  badge: "Tool: lane status", batch: "Tool: batch write", world_render: "Tool: lane view", highlight: "Tool: highlight",
};

const columns: Record<string, ColumnLabel> = {
  bench: { label: "Bench run" },
  date: { label: "Date" },
  test: { label: "Test", values: TESTS },
  compare: { label: "Comparison (A vs B)" },
  variant: { label: "Junction", values: SHAPES },
  shape: { label: "Junction", values: SHAPES },
  pair: { label: "Set" },
  faster: { label: "A faster", values: { yes: "Yes", no: "No" } },
  kmh_a: { label: "A speed", unit: " km/h", digits: 1 },
  kmh_b: { label: "B speed", unit: " km/h", digits: 1 },
  d_kmh: { label: "Speed A - B", unit: " km/h", digits: 1 },
  d_standing: { label: "Standing A - B", unit: " pp", digits: 1 },
  d_queue: { label: "Queue A - B", digits: 1 },
  thru_a: { label: "A cars / min", digits: 1 },
  thru_b: { label: "B cars / min", digits: 1 },
  d_thru: { label: "Cars / min A - B", digits: 1 },
  samples: { label: "Samples" },
  mode: { label: "Twin", values: MODES },
  check: { label: "Treatment check", values: { ok: "Passed", failed: "Failed" } },
  kmh: { label: "Speed", unit: " km/h", digits: 1 },
  standing: { label: "Standing", unit: " %", digits: 1 },
  queue: { label: "Queued 5 s+", digits: 1 },
  thru: { label: "Cars / min", digits: 1 },
  run: { label: "Showcase run" },
  session: { label: "Log session" },
  src: { label: "Source", values: { auto: "Automatic pass", tool: "Tool Apply", pick: "Tool pick" } },
  case: { label: "Case", values: { X: "Crossroads / T (X)", A: "One-way slip (A)", B: "Slip on a two-way road (B)", D: "Lane drop (D)", ring: "Roundabout", "-": "Not handled" } },
  finding: { label: "Main finding", values: FINDINGS },
  kinds: { label: "Findings" },
  findings: { label: "Findings (count)" },
  forced: { label: "Forced by the lane counts" },
  zone: { label: "In a test zone", values: { yes: "Yes", no: "No" } },
  clean: { label: "No junction flagged", values: { yes: "Clean", no: "Flagged" } },
  audited: { label: "Junctions audited" },
  flagged: { label: "Junctions flagged" },
  budget: { label: "Frame budget in the build", values: { yes: "Yes (rev 4 budget)", no: "No (one-frame jobs)" } },
  section: { label: "Section", values: SECTIONS },
  max_ms: { label: "Slowest call", unit: " ms", digits: 1 },
  over: { label: "Calls over 16 ms" },
  calls: { label: "Calls in the window" },
  file: { label: "Test file" },
  // "test" in the timing table is the test's name (a text column there)
  seconds: { label: "Time", unit: " s", digits: 3 },
};

const PAIR = { one: "pair", many: "pairs" };
const FASTER = { key: "faster", pass: "yes", passLabel: "A faster", failLabel: "B faster" };

export const dataSource = (dir: string): DataExplorerSource => ({
  dir,
  unit: PAIR,
  outcome: FASTER,
  columns,
  overviewTitle: "Pairs where the first twin was faster",
  intro: [
    "The raw numbers behind the other pages, as filterable tables: every side-by-side pair of the Stress Test benches and Lights showcase runs, every twin, the junction audit lines and SQPERF slow calls from the archived game logs, and the offline test timings.",
    "In the pair tables **A** is the first twin of the comparison (usually Smart Lanes) and **B** the second (usually the game's lanes); \"A faster\" splits the bars. Everything was re-read from the logs by `plans/square_smart_lanes/site/build_data.py`.",
  ],
  groups: [
    { key: "traffic", title: "Traffic", description: "Bench and showcase measurements." },
    { key: "audit", title: "Junction audit", description: "What the audit flagged in the logs." },
    { key: "perf", title: "Performance and tests" },
  ],
  datasets: [
    {
      file: "bench-pairs.json",
      title: "Bench pairs",
      group: "traffic",
      description: "Every A / B pair of the nine bench runs: both twins' speed and throughput and the differences.",
      notes: [
        "One row per pair and comparison: the same twin appears in every comparison it is part of (Smart Lanes vs game lanes, Smart Lanes vs its measuring modes).",
        "The two micro benches were stopped early on a saturated map: read their throughput (cars per minute), not their speed.",
      ],
      breakdown: "test",
      order: ["bench", "test", "compare", "variant", "pair", "faster", "d_kmh", "kmh_a", "kmh_b", "d_thru", "thru_a", "thru_b", "d_standing", "d_queue"],
    },
    {
      file: "showcase-pairs.json",
      title: "Lights showcase pairs",
      group: "traffic",
      description: "Runs 3 to 6 of the Lights showcase (lit crossroads and T-junctions), re-read with today's flow report.",
      notes: [
        "Runs 3 and 4 were jammed (towns three times the size) and their rig joined lanes one to one at the arms; run 5 fixed both, and that is where the sign of the 2x2 result flipped. Numbers can differ slightly from the ones recorded at the time (`RESULTS.md`), since the report has been improved since.",
      ],
      breakdown: "compare",
      order: ["run", "shape", "compare", "pair", "faster", "d_kmh", "kmh_a", "kmh_b", "d_standing"],
    },
    {
      file: "bench-twins.json",
      title: "Bench twins",
      group: "traffic",
      unit: { one: "twin", many: "twins" },
      outcome: { key: "check", pass: "ok", passLabel: "Got its mode", failLabel: "Failed the check" },
      description: "Every twin of the bench runs with its own numbers and whether it got the lanes its mode asks for.",
      breakdown: "mode",
      measure: "kmh",
      order: ["bench", "test", "mode", "variant", "kmh", "thru", "standing", "queue", "check"],
    },
    {
      file: "audit-junctions.json",
      title: "Audit findings",
      group: "audit",
      unit: { one: "flagged junction", many: "flagged junctions" },
      outcome: { key: "zone", pass: "yes", passLabel: "In a test zone", failLabel: "Elsewhere" },
      description: "Every junction the audit flagged with an avoidable finding, latest line per session, source and node.",
      notes: [
        "Only avoidable findings flag a junction; what the lane counts force (a 3 to 2 lane drop, a 2x2 crossroads sharing a lane) goes to the forced column. Many lines come from tool picks of the game's own lanes (source **Tool pick**), which is how the audit was meant to find inefficient layouts.",
      ],
      breakdown: "finding",
      measure: "count",
      hide: ["session"],
    },
    {
      file: "audit-jobs.json",
      title: "Audit per automatic job",
      group: "audit",
      unit: { one: "job", many: "jobs" },
      outcome: { key: "clean", pass: "yes", passLabel: "Clean", failLabel: "Flagged" },
      description: "One row per automatic pass after a build: junctions audited, junctions flagged and their findings.",
      breakdown: "date",
      hide: ["session"],
    },
    {
      file: "perf-slow.json",
      title: "Slow calls (SQPERF)",
      group: "perf",
      unit: { one: "slow line", many: "slow lines" },
      outcome: { key: "budget", pass: "yes", passLabel: "With the frame budget", failLabel: "One-frame jobs" },
      description: "Every Smart Lanes call over 16 ms the game logs recorded, per session: the frame budget of revision 4 shows as the drop in the slowest frame.",
      notes: [
        "A slow line is written even with the debug setting off: the slowest call of the 30-second window and how many calls were over 16 ms. **Frame budget in the build** is read from the log itself: only builds with the budget have the `job_step` instrument.",
      ],
      breakdown: "section",
      measure: "max_ms",
      hide: ["session"],
    },
    {
      file: "tests.json",
      title: "Offline test suite",
      group: "perf",
      unit: { one: "test", many: "tests" },
      description: "Every offline test of tests/square_smart_lanes with its last quick-mode time.",
      breakdown: "file",
      measure: "seconds",
    },
  ],
});
