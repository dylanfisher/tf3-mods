// Diverging dot-and-bar chart on the theme tokens, for differences that can go either way (A minus B per pair: km/h,
// cars per minute, ms). One row per comparison: a bar from zero to the row's mean, one dot per value (pair) around it,
// the zero line in the middle of a symmetric scale shared by every row, the mean and the "better" count at the tip, one
// tooltip per row (hover or keyboard focus) and a table view of the same numbers.
// Colors follow the dataviz rules: the bar is the theme's outcome pair, --chart-pass where the mean is better, --chart-fail
// where it is worse ("better" is higher or lower, a prop), never green / red; the side of zero and the signed number
// carry the same meaning, so color is never the only cue. Dots are neutral ink with a 2px surface ring. Labels in text
// tokens. Props are plain data, so Astro pages hydrate it with client:visible.
import { useId, useRef, useState, type FocusEvent, type PointerEvent, type ReactNode } from "react";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { fmt } from "@/lib/format";
import { cn } from "@/lib/utils";

interface DeltaRow {
  /** unique within the chart */
  key: string;
  label: string;
  /** one difference per pair (A minus B) */
  values: number[];
  /** muted second line in the tooltip and the table */
  hint?: string;
  /** link target of the row */
  href?: string;
}

interface DeltaChartProps {
  /** accessible name of the chart (and the table's caption) */
  title: string;
  rows: DeltaRow[];
  /** "higher" (default): a positive difference is better; "lower": a negative one is (standing share, ms) */
  better?: "higher" | "lower";
  /** legend and tooltip words for the two sides (default "Better" / "Worse") */
  labels?: { better: string; worse: string };
  /** decimals of the values */
  digits?: number;
  /** text after a value: " km/h" */
  unit?: string;
  /** header of the label column in the table view */
  rowHeader?: string;
  /** a line under the chart (hint, source) */
  footer?: ReactNode;
  className?: string;
}

const mean = (v: number[]) => (v.length ? v.reduce((a, b) => a + b, 0) / v.length : 0);

export default function DeltaChart({ title, rows, better = "higher", labels = { better: "Better", worse: "Worse" }, digits = 1, unit = "", rowHeader = "", footer, className }: DeltaChartProps) {
  const [view, setView] = useState<"chart" | "table">("chart");
  const [tip, setTip] = useState<{ key: string; x: number; y: number } | null>(null);
  const id = useId();
  const box = useRef<HTMLDivElement>(null);
  const sign = better === "higher" ? 1 : -1;
  const max = Math.max(1e-9, ...rows.flatMap((r) => r.values.map(Math.abs)));
  const pos = (v: number) => 50 + (v / max) * 50; // % of the plot width
  const val = (v: number) => `${v > 0 ? "+" : ""}${fmt(v, digits)}${unit}`;
  const stats = (r: DeltaRow) => {
    const m = mean(r.values);
    const good = r.values.filter((v) => v * sign > 0).length;
    return { m, good, n: r.values.length, lo: Math.min(...r.values), hi: Math.max(...r.values) };
  };
  const tipRow = tip ? rows.find((r) => r.key === tip.key) : undefined;

  return (
    <figure className={cn("m-0 min-w-0 rounded-xl border border-border bg-card p-3", className)}>
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <figcaption id={`${id}-t`} className="text-subhead font-semibold">{title}</figcaption>
        <div className="flex flex-wrap items-center gap-3">
          <ul className="flex flex-wrap gap-3 text-hint text-muted-foreground" aria-label="Legend">
            <li className="inline-flex items-center gap-1.5"><span className="inline-block size-2.5 rounded-[2px] bg-chart-pass" aria-hidden />{labels.better} (mean)</li>
            <li className="inline-flex items-center gap-1.5"><span className="inline-block size-2.5 rounded-[2px] bg-chart-fail" aria-hidden />{labels.worse} (mean)</li>
            <li className="inline-flex items-center gap-1.5"><span className="inline-block size-2 rounded-full bg-foreground/70 ring-2 ring-card" aria-hidden />one pair</li>
          </ul>
          <ToggleGroup aria-label="Show as" variant="outline" size="sm" spacing={0} value={[view]} onValueChange={(v) => { const x = (v as string[])[0]; if (x) setView(x as "chart" | "table"); }}>
            <ToggleGroupItem value="chart" className="data-[pressed]:bg-primary data-[pressed]:text-primary-foreground">Chart</ToggleGroupItem>
            <ToggleGroupItem value="table" className="data-[pressed]:bg-primary data-[pressed]:text-primary-foreground">Table</ToggleGroupItem>
          </ToggleGroup>
        </div>
      </div>

      {view === "chart" ? (
        <div ref={box} className="relative" onPointerLeave={() => setTip(null)}>
          <ul aria-labelledby={`${id}-t`} className="flex flex-col">
            {rows.map((r) => {
              const s = stats(r);
              const good = s.m * sign >= 0;
              const left = Math.min(pos(0), pos(s.m)), width = Math.abs(pos(s.m) - pos(0));
              const label = `${r.label}: mean ${val(s.m)}, ${labels.better.toLowerCase()} in ${s.good} of ${s.n}`;
              const body = (
                <>
                  <span className="min-w-0 truncate text-dense sm:text-right" title={r.label}>{r.label}</span>
                  <span className="flex min-w-0 items-center gap-2">
                    <span className="relative h-5 min-w-0 flex-1" aria-hidden>
                      <span className="absolute inset-y-0 left-1/2 w-px bg-border" />
                      <span
                        className={cn("absolute top-1/2 h-2.5 -translate-y-1/2", good ? "bg-chart-pass" : "bg-chart-fail", s.m >= 0 ? "rounded-r-[4px]" : "rounded-l-[4px]")}
                        style={{ left: `${left}%`, width: `max(${width}%, 1px)` }}
                      />
                      {r.values.map((v, k) => (
                        <span key={k} className="absolute top-1/2 size-2 -translate-1/2 rounded-full bg-foreground/70 ring-2 ring-card" style={{ left: `${pos(v)}%` }} />
                      ))}
                    </span>
                    <span className="w-28 shrink-0 text-hint whitespace-nowrap text-muted-foreground tabular-nums">{val(s.m)} · {s.good}/{s.n}</span>
                  </span>
                </>
              );
              const cls = cn(
                "grid w-full grid-cols-1 items-center gap-x-3 gap-y-0.5 rounded-md px-1.5 py-1 text-left sm:grid-cols-[minmax(0,15rem)_minmax(0,1fr)]",
                r.href && "cursor-pointer hover:bg-chip focus-visible:bg-chip",
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
                  {r.href ? <a href={r.href} className={cls} {...events}>{body}</a> : <div className={cls} tabIndex={0} {...events}>{body}</div>}
                </li>
              );
            })}
          </ul>
          <div className="grid grid-cols-1 gap-x-3 px-1.5 text-tag text-muted-foreground tabular-nums sm:grid-cols-[minmax(0,15rem)_minmax(0,1fr)]" aria-hidden>
            <span className="hidden sm:block" />
            <span className="flex items-center gap-2">
              <span className="flex flex-1 justify-between"><span>{val(-max)}</span><span>0</span><span>{val(max)}</span></span>
              <span className="w-28 shrink-0" />
            </span>
          </div>
          {tip && tipRow && (() => {
            const s = stats(tipRow);
            return (
              <div
                role="tooltip"
                className="pointer-events-none absolute z-10 max-w-64 -translate-x-1/2 -translate-y-full rounded-md border border-border bg-popover px-2.5 py-1.5 text-hint shadow-md"
                style={{ left: Math.min(Math.max(110, tip.x), (box.current?.clientWidth ?? 0) - 110), top: tip.y - 6 }}
              >
                <div className="mb-0.5 font-medium wrap-anywhere">{tipRow.label}</div>
                {tipRow.hint && <div className="mb-1 text-muted-foreground">{tipRow.hint}</div>}
                <div className="tabular-nums"><b className="font-semibold">{val(s.m)}</b> <span className="text-muted-foreground">mean of {s.n}</span></div>
                <div className="tabular-nums text-muted-foreground">{labels.better} in {s.good} of {s.n} · range {val(s.lo)} to {val(s.hi)}</div>
              </div>
            );
          })()}
        </div>
      ) : (
        <div className="max-h-[32rem] overflow-auto">
          <table className="w-full text-dense tabular-nums">
            <caption className="sr-only">{title}</caption>
            <thead>
              <tr className="border-b border-border text-left text-hint text-muted-foreground">
                <th className="py-1 pr-3 font-medium">{rowHeader}</th>
                <th className="py-1 pr-3 text-right font-medium">Pairs</th>
                <th className="py-1 pr-3 text-right font-medium">Mean</th>
                <th className="py-1 pr-3 text-right font-medium">{labels.better}</th>
                <th className="py-1 pr-3 text-right font-medium">Min</th>
                <th className="py-1 text-right font-medium">Max</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const s = stats(r);
                return (
                  <tr key={r.key} className="border-b border-border/60">
                    <td className="py-1 pr-3">{r.href ? <a className="text-brand-text hover:underline" href={r.href}>{r.label}</a> : r.label}{r.hint && <span className="block text-hint text-muted-foreground">{r.hint}</span>}</td>
                    <td className="py-1 pr-3 text-right">{s.n}</td>
                    <td className="py-1 pr-3 text-right">{val(s.m)}</td>
                    <td className="py-1 pr-3 text-right">{s.good}</td>
                    <td className="py-1 pr-3 text-right">{val(s.lo)}</td>
                    <td className="py-1 text-right">{val(s.hi)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {footer && <div className="mt-2 text-hint text-muted-foreground">{footer}</div>}
    </figure>
  );
}
