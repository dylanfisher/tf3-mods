// Small building blocks of the Name lab, on the shared shadcn (Base UI) widgets and theme tokens. Labelled selects and
// checkboxes are the site's own (components/site/fields.tsx).
import type { ReactNode } from "react";
import { Slider } from "@/components/ui/slider";
import { chipClass } from "@/lib/chip";
import { cn } from "@/lib/utils";
import { f2, u } from "./engine.ts";

/** A chip in the shared look (src/lib/chip.ts), the lab's compact size: no vertical padding, brand chips not bold. */
export function Pill({ children, tone, className, title }: { children: ReactNode; tone?: "ok" | "warn"; className?: string; title?: string }) {
  return (
    <span title={title} className={chipClass(tone === "ok" ? "brand" : tone === "warn" ? "warn" : "default", cn("py-0 font-normal", className))}>
      {children}
    </span>
  );
}

export function Muted({ children, className }: { children: ReactNode; className?: string }) {
  return <p className={cn("text-hint text-muted-foreground", className)}>{children}</p>;
}

/** Tag list as pills: "lake", "mere:0.6". */
function TagChips({ tl }: { tl?: [string, number][] }) {
  return (
    <>
      {(tl || []).map((p, i) => (
        <Pill key={i} className="mr-1">
          {p[0]}
          {p[1] !== 1 ? ":" + (+p[1]).toFixed(2).replace(/0+$/, "").replace(/\.$/, "") : ""}
        </Pill>
      ))}
    </>
  );
}

/* eslint-disable @typescript-eslint/no-explicit-any */
/** A parsed inventory entry: its tags and flags. */
export function EntryLine({ e }: { e: any }) {
  if (!e) return <>-</>;
  const bits: string[] = [];
  if (e.form) bits.push("form " + e.form);
  if (e.kind) bits.push(e.kind);
  if (e.grp) bits.push("@" + u(e.grp));
  if (e.rare) bits.push("rare");
  if (e.cls) bits.push("=" + u(e.cls));
  const fl = Object.keys(e.flags || {});
  if (fl.length) bits.push(fl.map((f) => "+" + f).join(" "));
  if (e.river) bits.push("the river's name");
  return (
    <>
      <TagChips tl={e.tl} /> <span className="text-muted-foreground">{bits.join(" · ")}</span>
    </>
  );
}

export const WeightPills = ({ list, max }: { list: [string, number][]; max?: number }) => (
  <>
    {list.slice(0, max ?? list.length).map((r) => (
      <Pill key={r[0]} className="mr-1">{r[0]} {f2(r[1])}</Pill>
    ))}
  </>
);

/** Bordered, horizontally scrolling table frame. */
export function TableBox({ children }: { children: ReactNode }) {
  return <div className="overflow-x-auto rounded-lg border border-border">{children}</div>;
}
export const th = "border-b border-border px-2 py-1.5 text-left align-top text-hint font-semibold text-muted-foreground";
export const td = "border-b border-border px-2 py-1.5 text-left align-top";

/** One-thumb slider over the shadcn Slider (which takes an array value). */
export function LabSlider({ label, value, onChange, min = 0, max = 1, step = 0.05, disabled, className }: {
  label: string; value: number; onChange: (v: number) => void; min?: number; max?: number; step?: number; disabled?: boolean; className?: string;
}) {
  return (
    <div className={cn("flex min-w-0 items-center", disabled && "opacity-40", className)}>
    <Slider
      aria-label={label}
      min={min}
      max={max}
      step={step}
      disabled={disabled}
      value={[value]}
      onValueChange={(v) => onChange(Array.isArray(v) ? v[0] : (v as number))}
    />
    </div>
  );
}
