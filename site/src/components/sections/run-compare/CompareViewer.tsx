// Island for one run comparison: the unit viewer (viewer/UnitViewer: A / B pick, side by side, slider, all runs in a
// row, category filter, prev / next, keys), the single-run gallery, the static run cards and key points (children,
// from RunCompareView.astro), the summary (median [quartiles] / sums, A / B ratio), the run table and the table of
// units a run created. Viewer first by default; RunCompareSource.order "details-first" puts the cards and tables
// first. State: A and B per page and the view per section are remembered (src/lib/storage.ts); the hash links a view:
// #view=all&unit=08&a=<run id>&b=<run id> (the older #town= is still read).
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { cap } from "@/lib/format";
import { asRecord } from "@/lib/storage";
import { usePersistentState } from "@/lib/use-persistent-state";
import type { CompareModel } from "./types";
import { ExtrasTable } from "./viewer/ExtrasTable";
import { RunRowsTable, SummaryTable } from "./viewer/MetricTable";
import { H2, Hint } from "./viewer/parts";
import { UnitGallery } from "./viewer/UnitGallery";
import { UnitViewer, VIEWS, type View } from "./viewer/UnitViewer";

const isView = (v: unknown): v is View => VIEWS.some((x) => x.value === v);

export default function CompareViewer({ model, children }: { model: CompareModel; children?: ReactNode }) {
  const { runs, units, single } = model;
  const viewerFirst = model.order !== "details-first";
  const multi = !single;
  const ids = useMemo(() => new Set(runs.map((r) => r.id)), [runs]);

  /** A valid pair: A a run, B another one; picking B as A (or A as B) swaps them. */
  const fixPair = useCallback((a: string, b: string, curA = a, curB = a): { a: string; b: string } => {
    if (!ids.has(a)) a = runs[0].id;
    if (a === b) b = curA === a ? curB : curA;
    if (!ids.has(b) || a === b) b = (runs.find((r) => r.id !== a) ?? runs[0]).id;
    return { a, b };
  }, [ids, runs]);

  const [pair, setPairState, pairReady] = usePersistentState(model.key, fixPair(runs[runs.length - 1].id, runs[0].id), (raw, d) => {
    const s = asRecord(raw);
    return fixPair(typeof s.a === "string" ? s.a : d.a, typeof s.b === "string" ? s.b : d.b);
  });
  const [viewState, setViewState, viewReady] = usePersistentState<{ view: View }>(`${model.sectionKey}/viewer`, { view: "side" }, (raw, d) => {
    const v = asRecord(raw).view;
    return { view: isView(v) ? v : d.view };
  });
  const { a: A, b: B } = pair;
  const view = viewState.view;
  const setView = useCallback((v: View | ((cur: View) => View)) => setViewState((s) => ({ view: typeof v === "function" ? v(s.view) : v })), [setViewState]);
  const [filter, setFilter] = useState("all");
  const [idx, setIdx] = useState(0);
  const [linked, setLinked] = useState(false);
  const unitsTitle = useRef<HTMLSpanElement>(null);

  // a hash link overrides what was remembered (once, after the restore)
  useEffect(() => {
    if (!pairReady || !viewReady || linked) return;
    const h = new URLSearchParams(location.hash.slice(1));
    const ha = h.get("a"), hb = h.get("b");
    if (ha || hb) setPairState((p) => fixPair(ha || p.a, hb || p.b));
    const v = h.get("view");
    if (isView(v)) setView(v);
    const nn = h.get("unit") ?? h.get("town");
    if (nn) { const k = units.findIndex((u) => u.nn === nn); if (k >= 0) setIdx(k); }
    setLinked(true);
  }, [pairReady, viewReady, linked, units, fixPair, setPairState, setView]);

  const visible = useMemo(() => {
    const v = units.filter((u) => filter === "all" || u.category === filter);
    return v.length ? v : units;
  }, [units, filter]);
  const cur = visible.includes(units[idx]) ? idx : units.indexOf(visible[0]);
  const t = units[cur];

  // the hash follows the view, so the address is a link to it
  useEffect(() => {
    if (!linked) return;
    const h = single ? `unit=${t.nn}` : `view=${view}&unit=${t.nn}&a=${encodeURIComponent(A)}&b=${encodeURIComponent(B)}`;
    history.replaceState(null, "", `#${h}`);
  }, [linked, A, B, view, t, single]);

  const setPair = useCallback((a: string, b: string) => setPairState((p) => fixPair(a, b, p.a, p.b)), [fixPair, setPairState]);
  const step = useCallback((d: number) => {
    const i = visible.indexOf(units[cur]);
    setIdx(units.indexOf(visible[(i + d + visible.length) % visible.length]));
  }, [visible, units, cur]);

  useEffect(() => {
    const onKey = (ev: KeyboardEvent) => {
      if (ev.metaKey || ev.ctrlKey || ev.altKey || ev.defaultPrevented) return;
      const el = ev.target as HTMLElement | null;
      if (el) {
        const tag = el.tagName;
        if (tag === "SELECT" || tag === "TEXTAREA" || el.isContentEditable) return;
        if (tag === "INPUT" && (el as HTMLInputElement).type !== "range") return;
        if (el.closest("[role=listbox],[role=combobox],[role=option],[role=menu]")) return;
      }
      if (ev.key === "ArrowLeft") { ev.preventDefault(); step(-1); }
      else if (ev.key === "ArrowRight") { ev.preventDefault(); step(1); }
      else if (single) return;
      else if (ev.key === "s" || ev.key === "S") setView((v) => ({ side: "slider", slider: "all", all: "side" } as const)[v]);
      else if (ev.key === "x" || ev.key === "X") setPair(B, A);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [step, single, setPair, setView, A, B]);

  const selectedRun = (id: string) => multi && (id === A || id === B);
  const pick = { runs, multi, A, B };

  // Blocks of the page, in the order the section's source asks for (RunCompareSource.order). `children` is the
  // static part from RunCompareView.astro (run cards, key points).
  const viewerBlock = (
    <UnitViewer
      model={model}
      A={A}
      B={B}
      view={view}
      filter={filter}
      visible={visible}
      current={cur}
      first={viewerFirst}
      titleRef={unitsTitle}
      on={{ pair: setPair, view: setView, filter: setFilter, pick: setIdx, step }}
    />
  );
  const galleryBlock = model.gallery && (
    <UnitGallery
      hint={model.gallery.hint}
      units={units}
      run={runs[0]}
      current={cur}
      extras={model.extras}
      onPick={(i) => { setFilter("all"); setIdx(i); unitsTitle.current?.scrollIntoView({ behavior: "smooth" }); }}
    />
  );
  const summaryBlock = (
    <>
      <H2>Summary</H2>
      <Hint className="mb-2">{model.summary.hint}</Hint>
      <SummaryTable rows={model.summary.rows} {...pick} />
    </>
  );
  const runTableBlock = model.runRows.length > 0 && (
    <>
      <H2>{cap(model.runName.many)}</H2>
      <RunRowsTable runs={runs} rows={model.runRows} selectedRun={selectedRun} first={cap(model.runName.one)} />
    </>
  );
  const extrasBlock = model.extras && <ExtrasTable extras={model.extras} unit={model.unit} runName={model.runName} runOf={(id) => runs.find((r) => r.id === id)!} />;
  const detailsBlock = children ? (viewerFirst ? <section><H2>Overview</H2>{children}</section> : children) : null;

  return viewerFirst ? (
    <div className="min-w-0">
      {/* single-run pages: the unit detail, then the gallery of every unit as its picker */}
      {viewerBlock}
      {galleryBlock}
      {detailsBlock}
      {summaryBlock}
      {runTableBlock}
      {extrasBlock}
    </div>
  ) : (
    <div className="min-w-0">
      {detailsBlock}
      {summaryBlock}
      {runTableBlock}
      {galleryBlock}
      {viewerBlock}
      {extrasBlock}
    </div>
  );
}
