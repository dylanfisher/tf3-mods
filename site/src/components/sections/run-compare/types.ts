// Generic kind "run-compare": game runs compared unit by unit (towns, junctions ...). Three layers:
//   RawCompare        the data a builder writes: <source.dir>/<page>/data.json (format below; plain data, no HTML)
//   RunCompareSource  the manifest section's `source`: where the data is plus every mod-specific label, sentence,
//                     metric row and formatter (build time only; functions allowed, their results go to the page)
//   CompareModel      what the viewer island receives: display-ready, serializable
// Wording that belongs to one mod (metric names, "town", category names, page sentences) lives in its
// RunCompareSource. Text shown from data or formatters is plain text with inline markup at most (**bold**, `code`;
// parseInline in src/lib/format.ts), never HTML.
// Only erasable TypeScript: manifests import these types (scripts/media.mjs runs them under Node).

// ---------------------------------------------------------------- data.json (written by a builder)

/** data.json versions the loader reads; anything else fails the build. */
export const RAW_VERSIONS = [2, 3] as const;

/** Per-run metrics of one unit. `name` and `shot` (relative to the page folder) are read by the kind; the rest is free. */
export interface RawMetrics {
  name?: string;
  shot?: string;
  [k: string]: unknown;
}

export interface RawRun {
  /** stable id within the page; keys of every per-run map */
  id: string;
  label: string;
  /** run kind, e.g. "mod" | "vanilla"; RunCompareSource.runKinds describes them */
  kind?: string;
  /** log session and map load (shown on list chips as a tooltip) */
  session?: string;
  load?: number | string;
  /** simulated years: a number, or a list of year rows whose last `.year` counts */
  years?: number | { year?: number | string }[];
  [k: string]: unknown;
}

export interface RawUnit {
  /** short display number, "01" (also the #unit= link key) */
  nn: string;
  /** per-run entity ids */
  ids?: Record<string, number | string | null>;
  /** per-run metrics (missing or null: the unit is not in that run) */
  m: Record<string, RawMetrics | null | undefined>;
  /** per-run extra facts, formatted by RunCompareSource.unitNotes / gallery */
  x?: Record<string, Record<string, unknown> | null | undefined>;
  /** per run: paired with the first run's unit by position instead of by id (version 2 data) */
  samePos?: Record<string, boolean>;
  /** verdict category key (RunCompareSource.categories), "unrated" or missing when none */
  category?: string;
  verdict?: string;
}

export interface RawExtra {
  name: string;
  shot?: string;
  [k: string]: unknown;
}

/** One summary metric of one run: [q1, median, q3, min, max] and the sum. */
export interface RawStat { q?: number[] | null; sum?: number | null }

export interface RawCompare {
  /** 3 (current); 2 is still read (towns / extraTowns, HTML key notes, header sentences that are now ignored) */
  version: number;
  /** one run: a gallery of every unit, no pairing (also when there is only one run) */
  single?: boolean;
  seed?: string | null;
  /** when the builder wrote it, "YYYY-MM-DD HH:MM": the comparison's date and sort order */
  built?: string;
  /** how the units were paired with the first run's: by entity id, or by id and else by position */
  pairing?: "id" | "id-or-position";
  header?: { title?: string; h1?: string };
  runs: RawRun[];
  units?: RawUnit[];
  /** per-run units a run created besides the paired ones (not in the summary) */
  extraUnits?: Record<string, RawExtra[]>;
  /** version 2 names of `units` and `extraUnits` */
  towns?: RawUnit[];
  extraTowns?: Record<string, RawExtra[]>;
  /** metric key -> run id -> stats */
  summary?: Record<string, Record<string, RawStat | undefined>>;
  /** keyNotes: hand-written key points (inline markup) */
  notes?: { keyNotes?: string[]; [k: string]: unknown };
  /** run table: [label, text per run ...], plain text */
  runRows?: (string | number | null)[][];
}

// ---------------------------------------------------------------- manifest source

export type CategoryTone = "run-0" | "run-1" | "run-2" | "run-3" | "muted";

export interface SummaryRow {
  label: string;
  /** key in data.json `summary` */
  key: string;
  /** "sum": the run's total; "q": median with the quartiles */
  mode: "sum" | "q";
  digits?: number;
  /** divide the shown value (not the ratio) by this, e.g. 1000 for m -> km */
  scale?: number;
}

export interface UnitRow {
  label: string;
  /** one run's cell: inline markup (**bold** for the main value) */
  cell: (m: RawMetrics) => string;
  /** metric whose A / B ratio fills the ratio column (none: empty) */
  ratioKey?: string;
}

export interface ExtraColumn {
  label: string;
  key: string;
  digits?: number;
}

/** What a page's sentences are built from (RunCompareSource.describe / autoNotes). */
export interface CompareFacts {
  seed: string;
  single: boolean;
  runs: RawRun[];
  /** paired units */
  units: number;
  /** created units per run id */
  extra: Record<string, number>;
  pairing: "id" | "id-or-position";
  summary: NonNullable<RawCompare["summary"]>;
  /** the data's notes as written (keyNotes and any data a builder put there for autoNotes / describe) */
  notes: NonNullable<RawCompare["notes"]>;
}

/** What is compared, singular and plural. */
export interface UnitNames { one: string; many: string }

export type RunCompareSource = {
  /** repo-relative folder holding one sub-folder per comparison with its data.json; shot paths are relative to it */
  dir: string;
  /** what is compared (default DEFAULT_UNIT from ./source: "unit" / "units") */
  unit?: UnitNames;
  /** what a run is called (default DEFAULT_RUN from ./source: "run" / "runs"; e.g. "twin" for side-by-side test twins) */
  runName?: UnitNames;
  /** chip and kind filter per run kind; `outline` draws a dashed chip (e.g. a vanilla reference run) */
  runKinds?: Record<string, { label: string; outline?: boolean }>;
  /** the run's card above the tables: lines of inline markup */
  runCard?: (run: RawRun) => string[];
  /** the page's one-line description (plain text; page header and meta description); default: runs and units */
  describe?: (d: CompareFacts) => string;
  /** key points generated from the data, after the hand-written ones (inline markup) */
  autoNotes?: (d: CompareFacts) => string[];
  /** note at the end of every comparison page (inline markup) */
  footer?: string;
  summaryRows: SummaryRow[];
  /** summary hint, multi-run and single-run pages */
  summaryHint?: { multi: string; single: string };
  unitRows: UnitRow[];
  /** one run's notes under the unit's table (plain text parts, joined with " · ") */
  unitNotes?: (x: Record<string, unknown>, m: RawMetrics) => string[];
  /** verdict categories: filter buttons, chip dot and tag */
  categories?: Record<string, { label: string; tag: string; tone: CategoryTone }>;
  /** prefix of a unit's verdict line, e.g. "0119 verdict:" */
  verdictLabel?: string;
  /** single-run pages: a card per unit */
  gallery?: {
    hint: string;
    /** [label, value] pairs (value: inline markup) */
    facts: (m: RawMetrics, x: Record<string, unknown> | undefined) => [string, string][];
    /** plain-text line under the facts */
    flags?: (m: RawMetrics, x: Record<string, unknown> | undefined) => string;
  };
  /** units a run created (data.json extraUnits) */
  extras?: {
    title: string;
    description: string;
    columns: ExtraColumn[];
    /** tag on gallery cards, e.g. "created" */
    tag?: string;
    facts?: (e: RawExtra) => [string, string][];
  };
  /** small note under the comparison list, e.g. how to add a page (inline markup) */
  listNote?: string;
  /**
   * Order of a comparison page. "viewer-first" (default): the unit viewer (pickers, view toggle, unit chips, images,
   * per-unit table; on single-run pages the unit detail and the gallery) right under the page header, then the run
   * cards, key points, summary, run table and extra units. "details-first": run cards, key points and tables first.
   */
  order?: CompareOrder;
};

export type CompareOrder = "viewer-first" | "details-first";

// ---------------------------------------------------------------- view model (sent to the island)

export interface Img {
  thumb: string;
  full: string;
  w: number;
  h: number;
  /** full-size width, for srcset */
  fw: number;
}

export interface ModelRun {
  id: string;
  label: string;
  /** 0..3: run color (src/lib/run-colors.ts) */
  color: number;
}

/** One summary cell: the shown value, the quartile range ("q" rows) and the raw number for the ratio column. */
export interface SummaryCell { text: string; range?: string; value: number | null }

export interface ModelUnit {
  nn: string;
  ids: string;
  category: string;
  verdict: string;
  /** per run: name, image, notes text (missing: not in that run) */
  runs: Record<string, { name: string; img?: Img; notes: string; facts?: [string, string][]; flags?: string }>;
  /** cells: inline markup per run */
  rows: { label: string; cells: Record<string, string>; ratio: Record<string, number | null> | null }[];
}

export interface ModelExtra {
  run: string;
  name: string;
  cells: string[];
  img?: Img;
  /** file name of the shot, for the link text */
  shotName?: string;
  facts?: [string, string][];
}

export interface CompareModel {
  order: CompareOrder;
  /** storage key of the page: "<modId>/<section>/<data folder>" (data names, not URLs) */
  key: string;
  /** storage key of the section, for what every page of it shares (the view) */
  sectionKey: string;
  single: boolean;
  unit: UnitNames;
  /** what a run is called (RunCompareSource.runName) */
  runName: UnitNames;
  runs: ModelRun[];
  summary: { hint: string; rows: { label: string; cells: Record<string, SummaryCell> }[] };
  runRows: { label: string; cells: string[] }[];
  units: ModelUnit[];
  categories: { value: string; label: string; tag: string; tone: CategoryTone }[];
  verdictLabel: string;
  gallery?: { hint: string };
  extras?: { title: string; description: string; columns: string[]; rows: ModelExtra[]; tag?: string };
}

/** Counts of a comparison, worded (list rows, page header). */
export interface EntryCounts {
  runs: { value: number; label: string };
  /** paired units, plus `extra` created ones */
  units: { value: number; label: string; extra: number };
  years: number | null;
}

/** A comparison as listed in the browser and used to build its page. */
export interface CompareEntry {
  /** URL segment (slugify(dir)) */
  slug: string;
  /** data folder under source.dir */
  dir: string;
  title: string;
  h1: string;
  /** plain text (RunCompareSource.describe) */
  description: string;
  seed: string;
  /** "YYYY-MM-DD" of `built` ("" when the data has none) */
  date: string;
  built: string;
  single: boolean;
  runs: { id: string; label: string; kind: string; session: string; load: string; years: number | null; card: string[] }[];
  units: number;
  extra: number;
  counts: EntryCounts;
  thumb?: Img;
  /** hand-written, then generated key points (inline markup) */
  keyNotes: string[];
  raw: RawCompare;
}
