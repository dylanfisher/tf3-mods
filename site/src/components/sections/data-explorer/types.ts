// Generic kind "data-explorer": result tables (one row per test, probe call, run ...) published as sub-pages with
// filters, a breakdown chart and a sortable table. Types of the manifest source and of the builder's data files
// (tools/site_table.py, data version 1). Only erasable TypeScript (manifests import the source type via define.ts).

/** Labels of one column: its name, its values' names, a unit for numbers. */
export interface ColumnLabel {
  label?: string;
  /** raw value -> label ("town_m" -> "Town medium"); unlisted values show as they are */
  values?: Record<string, string>;
  /** after a number: " ms", " m" */
  unit?: string;
  /** decimals of a number (default 0) */
  digits?: number;
}

/** The pass / fail column (charts split every bar into pass and fail). */
export interface Outcome {
  key: string;
  /** raw value that counts as pass ("true") */
  pass: string;
  passLabel: string;
  failLabel: string;
}

/** One data file = one sub-page. */
export interface DatasetDef {
  /** file name in source.dir, written by the builder (e.g. "probe-p5-all.json"); its stem is the page slug */
  file: string;
  title: string;
  /** a key of source.groups */
  group?: string;
  /** plain text: card and page header */
  description: string;
  /** paragraphs above the explorer (inline markup: **bold**, `code`) */
  notes?: string[];
  /** what one row is here, when not the section's unit */
  unit?: { one: string; many: string };
  /** this table's pass / fail column, when not the section's (it is then left out of the overview chart) */
  outcome?: Outcome;
  /** first "Break down by" column */
  breakdown?: string;
  /** first measure: "outcome" (default when the outcome varies), "count", or a numeric column (its median) */
  measure?: string;
  /** columns first in the filters and the table, in this order (the rest follow in file order) */
  order?: string[];
  /** columns left out of filters and table */
  hide?: string[];
}

export interface DataExplorerSource {
  /** repo-relative folder of the data files */
  dir: string;
  /** what one row is (default "row" / "rows") */
  unit?: { one: string; many: string };
  outcome?: Outcome;
  /** labels per column key, shared by every dataset */
  columns?: Record<string, ColumnLabel>;
  /** dataset groups on the section page, in order */
  groups?: { key: string; title: string; description?: string }[];
  /** paragraphs above the list on the section page (inline markup) */
  intro?: string[];
  /** title of the section page's overview chart (pass / fail per dataset; default "Pass and fail per dataset") */
  overviewTitle?: string;
  datasets: DatasetDef[];
}

/** A data file (tools/site_table.py). */
export type RawColumn =
  | { key: string; type: "cat"; values: string[]; data: number[] }
  | { key: string; type: "num"; data: (number | null)[] }
  /** many distinct strings (names): searched, never a filter */
  | { key: string; type: "text"; data: (string | null)[] };

export interface RawTable {
  version: 1;
  source: string;
  /** the source table's date (YYYY-MM-DD) */
  modified: string;
  rows: number;
  constant: Record<string, string>;
  columns: RawColumn[];
}

/** What the island gets besides the data URL (serializable). */
export interface ExplorerConfig {
  unit: { one: string; many: string };
  outcome?: Outcome;
  columns: Record<string, ColumnLabel>;
  breakdown?: string;
  measure?: string;
  order: string[];
  hide: string[];
}
