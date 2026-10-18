// Kind "data-explorer", one dataset (React island): fetches the data file, then filters (one select per categorical
// column), a breakdown chart (pass / fail share, count or a median per value of one column; a click on a bar filters
// by it) and a sortable, paged table of the filtered rows. Visitor choices persist per dataset.
import { useEffect, useMemo, useState } from "react";
import BarChart, { type BarRow } from "@/components/site/charts/BarChart";
import { LabeledSelect, type Option } from "@/components/site/fields";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { fmt } from "@/lib/format";
import { asRecord } from "@/lib/storage";
import { usePersistentState } from "@/lib/use-persistent-state";
import { cn } from "@/lib/utils";
import type { ExplorerConfig, RawColumn, RawTable } from "./types";

const PAGE = 50;
/** filters shown before "More filters" (the configured column order decides which) */
const FIRST_FILTERS = 6;

interface Kept {
  filters: Record<string, string>;
  breakdown: string;
  measure: string;
  sort: { key: string; desc: boolean } | null;
}

const median = (xs: number[]) => {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

export default function Explorer({ url, config, storageKey }: { url: string; config: ExplorerConfig; storageKey: string }) {
  const [table, setTable] = useState<RawTable | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [q, setQ] = useState("");
  const [allFilters, setAllFilters] = useState(false);

  useEffect(() => {
    let live = true;
    fetch(url)
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`${r.status} ${r.statusText}`))))
      .then((t: RawTable) => live && setTable(t))
      .catch((e: Error) => live && setError(e.message));
    return () => { live = false; };
  }, [url]);

  const label = (key: string) => config.columns[key]?.label ?? key;
  const valueLabel = (key: string, v: string) => config.columns[key]?.values?.[v] ?? v;

  // Visible columns: the configured order first, then file order, minus hidden ones.
  const columns = useMemo<RawColumn[]>(() => {
    if (!table) return [];
    const byKey = new Map(table.columns.map((c) => [c.key, c] as const));
    const keys = [...config.order.filter((k) => byKey.has(k)), ...table.columns.map((c) => c.key).filter((k) => !config.order.includes(k))];
    return keys.filter((k) => !config.hide.includes(k)).map((k) => byKey.get(k)!);
  }, [table, config.order, config.hide]);
  const cats = columns.filter((c): c is Extract<RawColumn, { type: "cat" }> => c.type === "cat" && c.values.length > 1);
  const nums = columns.filter((c) => c.type === "num");
  const texts = columns.filter((c): c is Extract<RawColumn, { type: "text" }> => c.type === "text");
  const outcomeCol = table?.columns.find((c) => c.key === config.outcome?.key && c.type === "cat") as Extract<RawColumn, { type: "cat" }> | undefined;
  const passIdx = outcomeCol && config.outcome ? outcomeCol.values.indexOf(config.outcome.pass) : -1;
  const hasOutcome = !!outcomeCol && outcomeCol.values.length > 1;

  const measures: Option[] = [
    ...(hasOutcome ? [{ value: "outcome", label: `${config.outcome!.passLabel} / ${config.outcome!.failLabel}` }] : []),
    { value: "count", label: `Count of ${config.unit.many}` },
    ...nums.map((c) => ({ value: c.key, label: `Median ${label(c.key)}` })),
  ];
  const defaults: Kept = {
    filters: {},
    breakdown: config.breakdown ?? "",
    measure: config.measure ?? "", // "" = the first measure (pass / fail when the outcome varies)
    sort: null,
  };
  const [kept, setKept] = usePersistentState<Kept>(storageKey, defaults, (raw, d) => {
    const s = asRecord(raw);
    const sort = asRecord(s.sort);
    return {
      filters: Object.fromEntries(Object.entries(asRecord(s.filters)).filter(([, v]) => typeof v === "string")) as Record<string, string>,
      breakdown: typeof s.breakdown === "string" ? s.breakdown : d.breakdown,
      measure: typeof s.measure === "string" ? s.measure : d.measure,
      sort: typeof sort.key === "string" ? { key: sort.key, desc: !!sort.desc } : null,
    };
  });

  // Valid choices once the data is in (stored ones may name columns this file lacks).
  const breakdown = cats.find((c) => c.key === kept.breakdown) ?? cats.find((c) => c.key !== config.outcome?.key) ?? cats[0];
  const measure = measures.some((m) => m.value === kept.measure) ? kept.measure : measures[0].value;
  const filters = Object.fromEntries(Object.entries(kept.filters).filter(([k, v]) => cats.some((c) => c.key === k && c.values.includes(v))));

  const rows = useMemo(() => {
    if (!table) return [] as number[];
    const active = Object.entries(filters).map(([k, v]) => {
      const c = cats.find((x) => x.key === k)!;
      return { data: c.data, idx: c.values.indexOf(v) };
    });
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const hay = (i: number) => texts.map((c) => c.data[i] ?? "").join(" ").toLowerCase();
    const out: number[] = [];
    for (let i = 0; i < table.rows; i++) {
      if (!active.every((f) => f.data[i] === f.idx)) continue;
      if (words.length && !words.every((w) => hay(i).includes(w))) continue;
      out.push(i);
    }
    if (kept.sort) {
      const c = columns.find((x) => x.key === kept.sort!.key);
      if (c) {
        const dir = kept.sort.desc ? -1 : 1;
        if (c.type === "text") out.sort((a, b) => (c.data[a] ?? "").localeCompare(c.data[b] ?? "") * dir || a - b);
        else {
          const val = c.type === "num" ? (i: number) => c.data[i] ?? -Infinity : (i: number) => c.data[i];
          out.sort((a, b) => (val(a) - val(b)) * dir || a - b);
        }
      }
    }
    return out;
  }, [table, JSON.stringify(filters), kept.sort, columns, q]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => setPage(0), [rows]);

  if (error) return <p className="rounded-xl border border-border bg-card p-4 text-dense text-muted-foreground">Could not load the data ({error}).</p>;
  if (!table) return <p className="py-6 text-dense text-muted-foreground">Loading the data…</p>;

  const passCount = hasOutcome ? rows.filter((i) => outcomeCol!.data[i] === passIdx).length : undefined;

  // Chart rows: one per value of the breakdown column present in the filtered rows.
  const chartRows: BarRow[] = [];
  if (breakdown) {
    const groups = new Map<number, number[]>();
    for (const i of rows) {
      const v = breakdown.data[i];
      if (!groups.has(v)) groups.set(v, []);
      groups.get(v)!.push(i);
    }
    const numCol = nums.find((c) => c.key === measure) as Extract<RawColumn, { type: "num" }> | undefined;
    for (const [v, ids] of [...groups.entries()].sort((a, b) => a[0] - b[0])) {
      const raw = v >= 0 ? breakdown.values[v] : "";
      const name = v >= 0 ? valueLabel(breakdown.key, raw) : "(none)";
      let values: number[];
      if (measure === "outcome") {
        const p = ids.filter((i) => outcomeCol!.data[i] === passIdx).length;
        values = [p, ids.length - p];
      } else if (numCol) {
        values = [median(ids.map((i) => numCol.data[i]).filter((x): x is number => x != null))];
      } else values = [ids.length];
      chartRows.push({ key: raw, label: name, values, hint: `${fmt(ids.length)} ${ids.length === 1 ? config.unit.one : config.unit.many}` });
    }
  }
  const numMeasure = nums.find((c) => c.key === measure);
  const cell = (c: RawColumn, i: number) => {
    if (c.type === "text") return c.data[i] ?? "-";
    if (c.type === "num") {
      const v = c.data[i];
      const l = config.columns[c.key];
      return v == null ? "-" : `${fmt(v, l?.digits ?? 0)}${l?.unit ?? ""}`;
    }
    const v = c.data[i];
    return v < 0 ? "-" : valueLabel(c.key, c.values[v]);
  };
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  const shown = rows.slice(page * PAGE, page * PAGE + PAGE);
  const setFilter = (k: string, v: string) => setKept((s) => ({ ...s, filters: { ...filters, [k]: v } }));
  const nFilters = Object.values(filters).filter(Boolean).length;

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div>
        <div className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="text-lg font-semibold tracking-tight">Filters</h2>
          <span className="text-hint text-muted-foreground tabular-nums">
            {rows.length === table.rows ? `${fmt(table.rows)} ${config.unit.many}` : `${fmt(rows.length)} of ${fmt(table.rows)} ${config.unit.many}`}
            {passCount != null && rows.length > 0 && ` · ${fmt(passCount)} ${config.outcome!.passLabel.toLowerCase()} (${fmt((passCount / rows.length) * 100, 1)}%)`}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {texts.length > 0 && (
            <Input
              type="search"
              value={q}
              onChange={(e) => setQ(e.currentTarget.value)}
              placeholder={`Search ${texts.map((c) => label(c.key).toLowerCase()).join(", ")}`}
              aria-label={`Search ${texts.map((c) => label(c.key).toLowerCase()).join(", ")}`}
              className="min-w-0 flex-[1_1_240px] bg-background"
            />
          )}
          {cats.filter((c, i) => allFilters || i < FIRST_FILTERS || filters[c.key]).map((c) => (
            <LabeledSelect
              key={c.key}
              label={label(c.key)}
              hideLabel
              value={filters[c.key] ?? ""}
              options={[{ value: "", label: `${label(c.key)}: all` }, ...c.values.map((v) => ({ value: v, label: `${label(c.key)}: ${valueLabel(c.key, v)}` }))]}
              onChange={(v) => setFilter(c.key, v)}
              triggerClassName={cn(filters[c.key] && "border-brand")}
            />
          ))}
          {cats.length > FIRST_FILTERS && (
            <Button variant="ghost" size="sm" aria-expanded={allFilters} onClick={() => setAllFilters((v) => !v)}>
              {allFilters ? "Fewer filters" : `More filters (${cats.length - FIRST_FILTERS})`}
            </Button>
          )}
          {nFilters > 0 && <Button variant="outline" size="sm" onClick={() => setKept((s) => ({ ...s, filters: {} }))}>Clear {nFilters} {nFilters === 1 ? "filter" : "filters"}</Button>}
        </div>
      </div>

      {breakdown && (
        <div>
          <div className="mb-2 flex flex-wrap items-center gap-x-4 gap-y-2">
            <LabeledSelect label="Break down by" value={breakdown.key} options={cats.map((c) => ({ value: c.key, label: label(c.key) }))} onChange={(v) => setKept((s) => ({ ...s, breakdown: v }))} />
            <LabeledSelect label="Measure" value={measure} options={measures} onChange={(v) => setKept((s) => ({ ...s, measure: v }))} />
          </div>
          {rows.length === 0 ? (
            <p className="py-3 text-dense text-muted-foreground">No {config.unit.many} match these filters.</p>
          ) : (
            <BarChart
              title={`${measures.find((m) => m.value === measure)?.label} by ${label(breakdown.key).toLowerCase()}`}
              series={measure === "outcome" ? [{ label: config.outcome!.passLabel, tone: "pass" }, { label: config.outcome!.failLabel, tone: "fail" }] : [{ label: measure === "count" ? config.unit.many : `Median ${label(measure)}`, tone: "pass" }]}
              rows={chartRows}
              mode={measure === "outcome" ? "share" : "value"}
              unit={numMeasure ? config.columns[numMeasure.key]?.unit ?? "" : ""}
              digits={numMeasure ? config.columns[numMeasure.key]?.digits ?? 0 : 0}
              rowHeader={label(breakdown.key)}
              selected={filters[breakdown.key]}
              onSelect={(r) => setFilter(breakdown.key, filters[breakdown.key] === r.key ? "" : r.key)}
              footer={`Click a bar to filter by that ${label(breakdown.key).toLowerCase()}; click it again to clear.`}
            />
          )}
        </div>
      )}

      <div>
        <div className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="text-lg font-semibold tracking-tight">Rows</h2>
          {pages > 1 && (
            <div className="flex items-center gap-2 text-hint text-muted-foreground tabular-nums">
              <Button variant="outline" size="sm" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>Previous</Button>
              <span>Page {page + 1} of {pages}</span>
              <Button variant="outline" size="sm" disabled={page >= pages - 1} onClick={() => setPage((p) => p + 1)}>Next</Button>
            </div>
          )}
        </div>
        <div className="max-w-full overflow-x-auto rounded-xl border border-border bg-card">
          <table className="w-full text-dense tabular-nums">
            <thead>
              <tr className="border-b border-border text-left text-hint text-muted-foreground">
                {columns.map((c) => {
                  const on = kept.sort?.key === c.key;
                  return (
                    <th key={c.key} className="px-2.5 py-1.5 font-medium whitespace-nowrap" aria-sort={on ? (kept.sort!.desc ? "descending" : "ascending") : "none"}>
                      <button
                        type="button"
                        className={cn("hover:text-foreground", on && "text-foreground")}
                        onClick={() => setKept((s) => ({ ...s, sort: on && s.sort ? (s.sort.desc ? null : { key: c.key, desc: true }) : { key: c.key, desc: false } }))}
                      >
                        {label(c.key)}{on ? (kept.sort!.desc ? " ↓" : " ↑") : ""}
                      </button>
                    </th>
                  );
                })}
              </tr>
            </thead>
            <tbody>
              {shown.map((i) => {
                const fail = hasOutcome && outcomeCol!.data[i] !== passIdx;
                return (
                  <tr key={i} className="border-b border-border/60 last:border-0">
                    {columns.map((c) => (
                      <td key={c.key} className={cn("px-2.5 py-1", c.type === "text" ? "min-w-64" : "whitespace-nowrap", c.type === "num" && "text-right", c.key === config.outcome?.key && fail && "font-semibold")}>
                        {cell(c, i)}
                      </td>
                    ))}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
