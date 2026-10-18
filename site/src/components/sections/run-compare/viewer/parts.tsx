// Small pieces of the comparison viewer (CompareViewer.tsx and the blocks in this folder).
import type { CSSProperties, ReactNode } from "react";
import { lightboxAttrs } from "@/lib/lightbox";
import Inline from "@/components/site/Inline";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { RUN_TEXT, runColor } from "@/lib/run-colors";
import { cn } from "@/lib/utils";
import type { Img, ModelRun, ModelUnit } from "../types";

/** The widest shot (one run, the slider): theme --container-shot; its srcset `sizes`. */
export const SHOT_SIZES = "(min-width: 1140px) 1120px, 100vw";

export const H2 = ({ children, id, first }: { children: ReactNode; id?: string; first?: boolean }) => (
  <h2 id={id} className={cn("mb-2.5 scroll-mt-chrome-pad text-lg font-semibold tracking-tight", first ? "mt-2" : "mt-7")}>{children}</h2>
);

export const Hint = ({ children, className }: { children: ReactNode; className?: string }) => (
  <p className={cn("text-hint text-muted-foreground", className)}>{children}</p>
);

const Box = ({ children, className }: { children: ReactNode; className?: string }) => (
  <div className={cn("min-w-0 rounded-xl border border-border bg-card px-2.5 py-1", className)}>{children}</div>
);

export const Tag = ({ children }: { children: ReactNode }) => (
  <span className="ml-1.5 inline-block rounded-full bg-chip px-2 align-[2px] text-tag font-normal text-muted-foreground">{children}</span>
);

export function RunName({ run, children }: { run: ModelRun; children?: ReactNode }) {
  return <span className={cn("font-semibold", RUN_TEXT[runColor(run.color)])}>{children ?? run.label}</span>;
}

/** Responsive <img>: thumb + full in srcset. */
export function Picture({ img, alt, sizes, className, eager, style }: { img: Img; alt: string; sizes: string; className?: string; eager?: boolean; style?: CSSProperties }) {
  return (
    <img
      src={img.full}
      srcSet={`${img.thumb} ${img.w}w, ${img.full} ${img.fw}w`}
      sizes={sizes}
      alt={alt}
      loading={eager ? "eager" : "lazy"}
      decoding="async"
      className={className}
      style={style}
    />
  );
}

export function NoShot({ className }: { className?: string }) {
  return (
    <div className={cn("flex aspect-video items-center justify-center rounded-lg border border-dashed border-border text-hint text-muted-foreground", className)}>
      no shot
    </div>
  );
}

/** One run's shot of a unit, with its caption. */
export function Shot({ unit, run, sizes }: { unit: ModelUnit; run: ModelRun; sizes: string }) {
  const r = unit.runs[run.id];
  return (
    <figure className="m-0 min-w-0">
      {r?.img ? (
        <a href={r.img.full} {...lightboxAttrs({ src: r.img.full, title: `${run.label}: ${r.name}` })} className="block">
          <Picture img={r.img} alt={`${run.label}: ${r.name}`} sizes={sizes} className="block aspect-video w-full rounded-lg border border-border bg-chip object-cover" />
        </a>
      ) : <NoShot />}
      <figcaption className="mt-1 text-dense"><RunName run={run} /> · {r?.name ?? "-"}</figcaption>
    </figure>
  );
}

/** [label, value] facts in a wrapping row; values are inline markup. */
export function Facts({ facts }: { facts?: [string, string][] }) {
  if (!facts?.length) return null;
  return (
    <div className="mx-0.5 mt-0.5 mb-1 flex flex-wrap gap-x-2.5 gap-y-0.5 text-hint text-muted-foreground tabular-nums">
      {facts.map(([k, v]) => (
        <span key={k}>{k} <b className="font-semibold text-foreground"><Inline text={v} /></b></span>
      ))}
    </div>
  );
}

const firstCol = "min-w-[180px] whitespace-normal text-left";
const head = "text-hint font-semibold text-muted-foreground";

/**
 * A bordered table of the comparison: a first column (label), then one column per run headed in the run's color (the
 * runs picked as A and B underlined), then optional columns (the A / B ratio). Cells are whatever the caller renders.
 */
export function RunTable({ first, runs, selected, align = "text-right", after = [], rows, empty }: {
  first: string;
  runs: ModelRun[];
  selected?: (id: string) => boolean;
  align?: "text-right" | "text-left";
  /** extra columns after the runs: header and alignment */
  after?: { label: string; className?: string }[];
  rows: { key: string; label: ReactNode; labelClass?: string; cells: ReactNode[]; cellClass?: string; after?: ReactNode[] }[];
  /** shown in one muted row when there are no rows */
  empty?: string;
}) {
  return (
    <Box>
      <Table className="text-dense tabular-nums">
        <TableHeader>
          <TableRow>
            <TableHead className={cn(firstCol, head)}>{first}</TableHead>
            {runs.map((r) => (
              <TableHead key={r.id} className={cn(align, "text-hint font-semibold", RUN_TEXT[runColor(r.color)], selected?.(r.id) && "shadow-[inset_0_-2px_0_currentColor]")}>
                {r.label}
              </TableHead>
            ))}
            {after.map((c) => <TableHead key={c.label} className={cn(head, c.className)}>{c.label}</TableHead>)}
          </TableRow>
        </TableHeader>
        <TableBody>
          {!rows.length && empty && (
            <TableRow><TableCell colSpan={1 + runs.length + after.length} className="text-muted-foreground">{empty}</TableCell></TableRow>
          )}
          {rows.map((row) => (
            <TableRow key={row.key}>
              <TableCell className={cn(firstCol, row.labelClass)}>{row.label}</TableCell>
              {row.cells.map((c, j) => <TableCell key={j} className={cn(align, row.cellClass)}>{c}</TableCell>)}
              {row.after?.map((c, j) => <TableCell key={`a${j}`} className={after[j]?.className}>{c}</TableCell>)}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Box>
  );
}
