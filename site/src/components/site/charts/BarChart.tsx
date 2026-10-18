// Horizontal bar chart on the theme tokens, for any page (React; static in Astro, interactive in an island): one bar per
// row, stacked when there are several series, with a legend (two or more series), the value at each bar's tip, one
// tooltip per row (hover or keyboard focus: every series of the row) and a table view of the same numbers.
// Marks follow the dataviz rules: bars 16px thick with a 4px rounded end, a 2px surface gap between stacked segments,
// labels in text tokens (never the series color), series colors from SERIES_FILL (validated pairs, theme.css).
// Props are plain data, so Astro pages can pass them to a hydrated island (client:visible).
import { useId, useRef, useState, type FocusEvent, type PointerEvent, type ReactNode } from "react";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { fmt } from "@/lib/format";
import { cn } from "@/lib/utils";

/** Series fills: "pass" / "fail" are the outcome pair (theme --chart-pass / --chart-fail); a single series uses "pass". */
const SERIES_FILL = { pass: "bg-chart-pass", fail: "bg-chart-fail" } as const;
type SeriesTone = keyof typeof SERIES_FILL;

interface BarSeries {
  label: string;
  tone: SeriesTone;
}

export interface BarRow {
  /** unique within the chart */
  key: string;
  label: string;
  /** one value per series */
  values: number[];
  /** link target of the row (e.g. a sub-page) */
  href?: string;
  /** muted second line in the tooltip and the table */
  hint?: string;
}

interface BarChartProps {
  /** accessible name of the chart (and the table's caption) */
  title: string;
  series: BarSeries[];
  rows: BarRow[];
  /**
   * "share": every bar is the row's total split into its series (100%), the tip shows the first series' share and the
   * counts ("67% · 1,316 of 1,970"). "value": bar length is the row's total against the largest one; the tip shows it.
   */
  mode?: "share" | "value";
  /** decimals of the values (value mode) */
  digits?: number;
  /** text after a value: " ms", " m" */
  unit?: string;
  /** header of the label column in the table view */
  rowHeader?: string;
  /** the row key shown as selected (islands: the active filter) */
  selected?: string;
  /** islands only: click on a row (rows with href navigate instead) */
  onSelect?: (row: BarRow) => void;
  /** a line under the chart (hint, source) */
  footer?: ReactNode;
  className?: string;
}

const pct = (n: number, total: number) => (total ? Math.round((n / total) * 1000) / 10 : 0);

export default function BarChart({ title, series, rows, mode = "share", digits = 0, unit = "", rowHeader = "", selected, onSelect, footer, className }: BarChartProps) {
  const [view, setView] = useState<"chart" | "table">("chart");
  const [tip, setTip] = useState<{ key: string; x: number; y: number } | null>(null);
  const id = useId();
  const box = useRef<HTMLDivElement>(null);
  const totals = rows.map((r) => r.values.reduce((a, b) => a + b, 0));
  const max = Math.max(1, ...totals);
  const value = (v: number) => `${fmt(v, digits)}${unit}`;
  const tipText = (r: BarRow, total: number) =>
    mode === "share" ? `${fmt(pct(r.values[0], total), 1)}% · ${fmt(r.values[0])} of ${fmt(total)}` : value(total);
  const tipRow = tip ? rows.find((r) => r.key === tip.key) : undefined;

  return (
    <figure className={cn("m-0 min-w-0 rounded-xl border border-border bg-card p-3", className)}>
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <figcaption id={`${id}-t`} className="text-subhead font-semibold">{title}</figcaption>
        <div className="flex flex-wrap items-center gap-3">
          {series.length > 1 && (
            <ul className="flex flex-wrap gap-3 text-hint text-muted-foreground" aria-label="Legend">
              {series.map((s) => (
                <li key={s.label} className="inline-flex items-center gap-1.5">
                  <span className={cn("inline-block size-2.5 rounded-[2px]", SERIES_FILL[s.tone])} aria-hidden />
                  {s.label}
                </li>
              ))}
            </ul>
          )}
          <ToggleGroup aria-label="Show as" variant="outline" size="sm" spacing={0} value={[view]} onValueChange={(v) => { const x = (v as string[])[0]; if (x) setView(x as "chart" | "table"); }}>
            <ToggleGroupItem value="chart" className="data-[pressed]:bg-primary data-[pressed]:text-primary-foreground">Chart</ToggleGroupItem>
            <ToggleGroupItem value="table" className="data-[pressed]:bg-primary data-[pressed]:text-primary-foreground">Table</ToggleGroupItem>
          </ToggleGroup>
        </div>
      </div>

      {view === "chart" ? (
        <div ref={box} className="relative" onPointerLeave={() => setTip(null)}>
          <ul aria-labelledby={`${id}-t`} className="flex flex-col">
            {rows.map((r, i) => {
              const total = totals[i];
              const frac = mode === "share" ? 1 : total / max;
              const shown = r.values.map((v, s) => ({ v, s })).filter((x) => x.v > 0);
              const label = `${r.label}: ${series.map((s, k) => `${s.label} ${value(r.values[k])}`).join(", ")}`;
              const body = (
                <>
                  <span className="min-w-0 truncate text-dense sm:text-right" title={r.label}>{r.label}</span>
                  <span className="flex min-w-0 items-center gap-2">
                    <span className="flex h-4 min-w-0 flex-[0_1_auto] gap-0.5" style={{ width: `calc((100% - 9.5rem) * ${frac})` }} aria-hidden>
                      {shown.length === 0 ? <span className="h-full w-px bg-border" /> : shown.map(({ v, s }, k) => (
                        <span
                          key={s}
                          className={cn("h-full min-w-px", SERIES_FILL[series[s]?.tone ?? "pass"], k === shown.length - 1 && "rounded-r-[4px]")}
                          style={{ flex: `${v} 1 0` }}
                        />
                      ))}
                    </span>
                    <span className="shrink-0 text-hint whitespace-nowrap text-muted-foreground tabular-nums">{tipText(r, total)}</span>
                  </span>
                </>
              );
              const cls = cn(
                "grid w-full grid-cols-1 items-center gap-x-3 gap-y-0.5 rounded-md px-1.5 py-1 text-left sm:grid-cols-[minmax(0,13rem)_minmax(0,1fr)]",
                (r.href || onSelect) && "cursor-pointer hover:bg-chip focus-visible:bg-chip",
                selected === r.key && "bg-chip ring-1 ring-brand",
              );
              const events = {
                onPointerMove: (e: PointerEvent) => {
                  const b = box.current?.getBoundingClientRect();
                  if (b) setTip({ key: r.key, x: e.clientX - b.left, y: e.clientY - b.top });
                },
                onFocus: (e: FocusEvent) => {
                  const b = box.current?.getBoundingClientRect();
                  const el = e.currentTarget.getBoundingClientRect();
                  if (b) setTip({ key: r.key, x: el.left - b.left + el.width / 2, y: el.top - b.top });
                },
                onBlur: () => setTip(null),
                "aria-label": label,
              };
              return (
                <li key={r.key}>
                  {r.href ? (
                    <a href={r.href} className={cls} {...events}>{body}</a>
                  ) : onSelect ? (
                    <button type="button" className={cls} aria-pressed={selected === r.key} onClick={() => onSelect(r)} {...events}>{body}</button>
                  ) : (
                    <div className={cls} tabIndex={0} {...events}>{body}</div>
                  )}
                </li>
              );
            })}
          </ul>
          {tip && tipRow && (
            <div
              role="tooltip"
              className="pointer-events-none absolute z-10 max-w-64 -translate-x-1/2 -translate-y-full rounded-md border border-border bg-popover px-2.5 py-1.5 text-hint shadow-md"
              style={{ left: Math.min(Math.max(100, tip.x), (box.current?.clientWidth ?? 0) - 100), top: tip.y - 6 }}
            >
              <div className="mb-0.5 font-medium wrap-anywhere">{tipRow.label}</div>
              {tipRow.hint && <div className="mb-1 text-muted-foreground">{tipRow.hint}</div>}
              {series.map((s, k) => {
                const total = tipRow.values.reduce((a, b) => a + b, 0);
                return (
                  <div key={s.label} className="flex items-center gap-2 tabular-nums">
                    <span className={cn("inline-block h-0.5 w-3", SERIES_FILL[s.tone])} aria-hidden />
                    <b className="font-semibold">{value(tipRow.values[k])}</b>
                    <span className="text-muted-foreground">{s.label}{mode === "share" && series.length > 1 ? ` · ${fmt(pct(tipRow.values[k], total), 1)}%` : ""}</span>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      ) : (
        <div className="max-h-[32rem] overflow-auto">
          <table className="w-full text-dense tabular-nums">
            <caption className="sr-only">{title}</caption>
            <thead>
              <tr className="border-b border-border text-left text-hint text-muted-foreground">
                <th className="py-1 pr-3 font-medium">{rowHeader}</th>
                {series.map((s) => <th key={s.label} className="py-1 pr-3 text-right font-medium">{s.label}</th>)}
                {series.length > 1 && <th className="py-1 pr-3 text-right font-medium">Total</th>}
                {mode === "share" && series.length > 1 && <th className="py-1 text-right font-medium">{series[0].label} %</th>}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={r.key} className="border-b border-border/60">
                  <td className="py-1 pr-3">{r.href ? <a className="text-brand-text hover:underline" href={r.href}>{r.label}</a> : r.label}{r.hint && <span className="block text-hint text-muted-foreground">{r.hint}</span>}</td>
                  {r.values.map((v, k) => <td key={k} className="py-1 pr-3 text-right">{value(v)}</td>)}
                  {series.length > 1 && <td className="py-1 pr-3 text-right">{value(totals[i])}</td>}
                  {mode === "share" && series.length > 1 && <td className="py-1 text-right">{fmt(pct(r.values[0], totals[i]), 1)}%</td>}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {footer && <div className="mt-2 text-hint text-muted-foreground">{footer}</div>}
    </figure>
  );
}
