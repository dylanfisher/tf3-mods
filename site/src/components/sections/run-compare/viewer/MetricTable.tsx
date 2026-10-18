// The metric tables of a comparison: the summary (median [quartiles] or sums per run) and one unit's metrics, both
// with the A / B ratio column on multi-run pages.
import Inline from "@/components/site/Inline";
import { ratio } from "@/lib/format";
import type { CompareModel, ModelRun, ModelUnit } from "../types";
import { RunTable } from "./parts";

interface Pick { runs: ModelRun[]; multi: boolean; A: string; B: string }

const RATIO = [{ label: "A / B", className: "text-right" }];
const selected = ({ multi, A, B }: Pick) => (id: string) => multi && (id === A || id === B);

export function SummaryTable({ rows, ...p }: Pick & { rows: CompareModel["summary"]["rows"] }) {
  return (
    <RunTable
      first="Metric"
      runs={p.runs}
      selected={selected(p)}
      after={p.multi ? RATIO : []}
      rows={rows.map((row) => ({
        key: row.label,
        label: row.label,
        cells: p.runs.map((r) => {
          const c = row.cells[r.id];
          if (!c || c.range == null) return c?.text ?? "-";
          return <><b>{c.text}</b> <span className="text-tag text-muted-foreground">{c.range}</span></>;
        }),
        after: p.multi ? [ratio(row.cells[p.A]?.value, row.cells[p.B]?.value)] : undefined,
      }))}
    />
  );
}

export function UnitTable({ unit, ...p }: Pick & { unit: ModelUnit }) {
  return (
    <RunTable
      first="Metric"
      runs={p.runs}
      selected={selected(p)}
      after={p.multi ? RATIO : []}
      rows={unit.rows.map((row) => ({
        key: row.label,
        label: row.label,
        cells: p.runs.map((r) => <Inline text={row.cells[r.id]} />),
        after: p.multi ? [row.ratio && unit.runs[p.A] && unit.runs[p.B] ? ratio(row.ratio[p.A], row.ratio[p.B]) : ""] : undefined,
      }))}
    />
  );
}

/** The run table: one row per fact, a text per run (plain text from the data). */
export function RunRowsTable({ runs, rows, selectedRun, first = "Run" }: { runs: ModelRun[]; rows: CompareModel["runRows"]; selectedRun: (id: string) => boolean; first?: string }) {
  return (
    <RunTable
      first={first}
      runs={runs}
      selected={selectedRun}
      align="text-left"
      rows={rows.map((row, i) => ({
        key: String(i),
        label: row.label,
        labelClass: "align-top",
        cells: row.cells,
        cellClass: "min-w-[160px] align-top text-hint whitespace-normal",
      }))}
    />
  );
}
