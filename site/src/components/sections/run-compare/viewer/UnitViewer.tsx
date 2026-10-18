// The unit viewer: run pickers (A, B, swap), view (side by side, slider, all runs), category filter, prev / next, the
// unit chips, then the unit: heading, verdict, shots, metric table and per-run notes. Its own box: the sticky toolbar
// stays within the viewer and never covers the tables below it.
import type { CSSProperties, Ref } from "react";
import { ArrowLeft, ArrowLeftRight, ArrowRight } from "lucide-react";
import { LabeledSelect } from "@/components/site/fields";
import { Button } from "@/components/ui/button";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { cap } from "@/lib/format";
import { TONE_BG } from "@/lib/run-colors";
import { cn } from "@/lib/utils";
import type { CompareModel, ModelRun, ModelUnit } from "../types";
import { UnitTable } from "./MetricTable";
import { H2, RunName, Shot, SHOT_SIZES, Tag } from "./parts";
import { ShotSlider } from "./ShotSlider";

export type View = "side" | "slider" | "all";
export const VIEWS: { value: View; label: string }[] = [
  { value: "side", label: "Side by side" },
  { value: "slider", label: "Slider" },
  { value: "all", label: "All runs" },
];

const pressedItem = "data-[pressed]:bg-brand data-[pressed]:text-on-brand data-[pressed]:hover:bg-brand/90";

export function UnitViewer({ model, A, B, view, filter, visible, current, first, titleRef, on }: {
  model: CompareModel;
  A: string;
  B: string;
  view: View;
  filter: string;
  /** the units the filter keeps */
  visible: ModelUnit[];
  /** index of the shown unit in model.units */
  current: number;
  /** the first block of the page (less space above) */
  first: boolean;
  titleRef: Ref<HTMLSpanElement>;
  on: { pair: (a: string, b: string) => void; view: (v: View) => void; filter: (f: string) => void; pick: (index: number) => void; step: (d: number) => void };
}) {
  const { runs, units, single, unit } = model;
  const multi = !single;
  const runOf = (id: string) => runs.find((r) => r.id === id)!;
  const a = runOf(A), b = runOf(B);
  const t = units[current];
  const catOf = (c: string) => model.categories.find((x) => x.value === c);
  const cat = catOf(t.category);
  // one name when every run calls the unit the same (side-by-side twins of one test set), else each run's in its color
  const names = [...new Set(Object.values(t.runs).map((r) => r.name))];
  const sameName = names.length === 1 ? names[0] : null;
  const runItems = runs.map((r) => ({ value: r.id, label: r.label }));
  const pick = (label: "A" | "B", value: string, set: (v: string) => void) => (
    <LabeledSelect label={label} ariaLabel={`${cap(model.runName.one)} ${label}`} value={value} options={runItems} onChange={(v) => v && set(v)} triggerClassName="max-w-[min(260px,70vw)]" />
  );

  let imgs;
  if (single) imgs = <div className="mx-auto max-w-shot"><Shot unit={t} run={runs[0]} sizes={SHOT_SIZES} /></div>;
  else if (view === "side") imgs = <div className="grid gap-2.5 md:grid-cols-2"><Shot unit={t} run={a} sizes="(min-width: 768px) 50vw, 100vw" /><Shot unit={t} run={b} sizes="(min-width: 768px) 50vw, 100vw" /></div>;
  else if (view === "all")
    imgs = (
      <div className="grid gap-2.5 md:grid-cols-[repeat(var(--n),minmax(0,1fr))]" style={{ "--n": runs.length } as CSSProperties}>
        {runs.map((r: ModelRun) => <Shot key={r.id} unit={t} run={r} sizes={`(min-width: 768px) ${Math.ceil(100 / runs.length)}vw, 100vw`} />)}
      </div>
    );
  else imgs = <ShotSlider key={`${t.nn}-${A}-${B}`} unit={t} a={a} b={b} />;

  return (
    <div className="min-w-0">
      <H2 id="units" first={first}>
        <span ref={titleRef} className="scroll-mt-chrome-pad">{single ? `${cap(unit.one)} detail` : cap(unit.many)}</span>
      </H2>
      <div className="z-30 flex flex-wrap items-center gap-2 border-b border-border bg-background py-2.5 md:sticky md:top-chrome">
        {multi && (
          <>
            {pick("A", A, (v) => on.pair(v, B))}
            {pick("B", B, (v) => on.pair(A, v))}
            <Button variant="outline" size="icon" title="Swap A and B" aria-label="Swap A and B" onClick={() => on.pair(B, A)}>
              <ArrowLeftRight />
            </Button>
            <ToggleGroup aria-label="View" variant="outline" spacing={0} value={[view]} onValueChange={(v) => v[0] && on.view(v[0] as View)}>
              {VIEWS.map((v) => <ToggleGroupItem key={v.value} value={v.value} className={pressedItem}>{v.value === "all" ? `All ${model.runName.many}` : v.label}</ToggleGroupItem>)}
            </ToggleGroup>
            {model.categories.length > 0 && (
              <ToggleGroup aria-label="Filter" variant="outline" spacing={0} value={[filter]} onValueChange={(v) => v[0] && on.filter(v[0] as string)}>
                <ToggleGroupItem value="all" className={pressedItem}>All</ToggleGroupItem>
                {model.categories.map((c) => <ToggleGroupItem key={c.value} value={c.value} className={pressedItem}>{c.label}</ToggleGroupItem>)}
              </ToggleGroup>
            )}
          </>
        )}
        <Button variant="outline" onClick={() => on.step(-1)}><ArrowLeft data-icon="inline-start" />Prev</Button>
        <Button variant="outline" onClick={() => on.step(1)}>Next<ArrowRight data-icon="inline-end" /></Button>
        <span className="hidden flex-1 md:block" />
        <span className="hidden text-meta text-muted-foreground md:inline">
          {multi
            ? <>Keys: ← / → {unit.one}, S view, X swap A / B · link: #view=all&amp;unit=08&amp;a=&lt;{model.runName.one} id&gt;</>
            : <>Keys: ← / → {unit.one} · link: #unit=08</>}
        </span>
      </div>

      <div className="my-3 flex flex-wrap gap-1.5" role="group" aria-label={cap(unit.many)}>
        {visible.map((u) => {
          const i = units.indexOf(u);
          const c = catOf(u.category);
          return (
            <button
              key={u.nn}
              type="button"
              aria-current={i === current ? "true" : undefined}
              onClick={() => on.pick(i)}
              className={cn(
                "inline-flex max-w-[280px] items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-hint whitespace-nowrap",
                i === current ? "border-brand bg-card font-semibold" : "border-transparent bg-chip hover:border-border",
              )}
            >
              <span className={cn("size-[7px] shrink-0 rounded-full", c ? TONE_BG[c.tone] : "bg-border")} aria-hidden="true" />
              <span className="truncate">{u.nn} {(u.runs[A] ?? Object.values(u.runs)[0])?.name ?? "-"}</span>
            </button>
          );
        })}
      </div>

      <section aria-live="polite">
        <h2 className="mt-1.5 mb-0.5 text-lg font-semibold tracking-tight wrap-anywhere">
          {t.nn} ·{" "}
          {sameName ? sameName : runs.map((r, i) => (
            <span key={r.id}>{i > 0 && <span className="font-normal text-muted-foreground"> / </span>}<RunName run={r}>{t.runs[r.id]?.name ?? "-"}</RunName></span>
          ))}
          {cat && <Tag>{cat.tag}</Tag>}
          {t.ids && <Tag>id {t.ids}</Tag>}
        </h2>
        {t.verdict && <p className="mt-1 mb-3"><span className="text-hint text-muted-foreground">{model.verdictLabel}</span> {t.verdict}</p>}
        <div className="mt-2">{imgs}</div>
        <div className="mt-3"><UnitTable unit={t} runs={runs} multi={multi} A={A} B={B} /></div>
        {runs.map((r) => t.runs[r.id]?.notes ? (
          <p key={r.id} className="mt-2 text-dense wrap-anywhere text-muted-foreground"><RunName run={r} />: {t.runs[r.id].notes}.</p>
        ) : null)}
      </section>
    </div>
  );
}
