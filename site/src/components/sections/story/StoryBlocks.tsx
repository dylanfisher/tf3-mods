// Renders story blocks (sections/story/types.ts). Static HTML in Astro; the interactive ones (compare, bars, deltas) work when
// hydrated (Story.astro hydrates only those in articles; StoryList hydrates everything).
import type { CSSProperties } from "react";
import BeforeAfter from "@/components/site/BeforeAfter";
import BarChart from "@/components/site/charts/BarChart";
import DeltaChart from "@/components/site/charts/DeltaChart";
import Inline from "@/components/site/Inline";
import Mosaic from "@/components/site/Mosaic";
import { lightboxAttrs } from "@/lib/lightbox";
import { slugify } from "@/lib/slug";
import { cn } from "@/lib/utils";
import type { ResolvedBlock, ResolvedImage } from "./model";

const Picture = ({ img, className, style, sizes = "(min-width: 1140px) 1100px, 100vw" }: { img: ResolvedImage; className?: string; style?: CSSProperties; sizes?: string }) => (
  <img
    src={img.full}
    srcSet={`${img.thumb} ${img.w}w, ${img.full} ${img.fw}w`}
    sizes={sizes}
    alt={img.caption ?? ""}
    loading="lazy"
    decoding="async"
    className={className}
    style={style}
  />
);

function Figure({ img, sizes }: { img: ResolvedImage; sizes?: string }) {
  return (
    <figure className="m-0 min-w-0">
      <a href={img.full} {...lightboxAttrs({ src: img.full, title: img.caption ?? "" })} className="block overflow-hidden rounded-lg border border-border bg-chip hover:border-brand">
        <Picture img={img} sizes={sizes} className="block h-auto w-full" />
      </a>
      {img.caption && <figcaption className="mt-1.5 text-hint text-muted-foreground"><Inline text={img.caption} /></figcaption>}
    </figure>
  );
}

export function StoryBlock({ block: b }: { block: ResolvedBlock }) {
  switch (b.type) {
    case "p":
      return <p className="max-w-[72ch]"><Inline text={b.text} /></p>;
    case "list": {
      const L = b.ordered ? "ol" : "ul";
      return (
        <L className={cn("max-w-[72ch] pl-5", b.ordered ? "list-decimal" : "list-disc")}>
          {b.items.map((t, i) => <li key={i} className="mt-1 first:mt-0"><Inline text={t} /></li>)}
        </L>
      );
    }
    case "parts":
      return (
        <dl className="grid max-w-[80ch] grid-cols-1 gap-x-4 gap-y-1.5 sm:grid-cols-[7rem_minmax(0,1fr)]">
          {b.parts.map((p, i) => (
            <div key={i} className="contents">
              <dt className="pt-px text-hint font-semibold tracking-[0.04em] text-muted-foreground uppercase">{p.label}</dt>
              <dd className="mb-1.5 sm:mb-0"><Inline text={p.text} /></dd>
            </div>
          ))}
        </dl>
      );
    case "figure":
      return <Figure img={b.image} />;
    case "gallery":
      return (
        <div className={cn("grid grid-cols-1 items-start gap-3 sm:grid-cols-2", b.images.length > 2 && "lg:grid-cols-3")}>
          {b.images.map((img) => <Figure key={img.src} img={img} sizes="(min-width: 640px) 50vw, 100vw" />)}
        </div>
      );
    case "compare":
      return (
        <figure className="m-0">
          <BeforeAfter
            ratio={b.before.w / b.before.h}
            left={{ label: b.before.label, render: (p) => <Picture img={b.before} {...p} /> }}
            right={{ label: b.after.label, render: (p) => <Picture img={b.after} {...p} /> }}
          />
          {b.caption && <figcaption className="mt-1.5 text-hint text-muted-foreground"><Inline text={b.caption} /></figcaption>}
        </figure>
      );
    case "pairs":
      return (
        <div className={cn("grid grid-cols-1 items-start gap-4", b.columns !== 1 && "md:grid-cols-2")}>
          {b.pairs.map((p) => (
            <figure key={p.before.src + p.after.src} className="m-0 min-w-0">
              <BeforeAfter
                ratio={p.before.w / p.before.h}
                left={{ label: p.before.label, render: (q) => <Picture img={p.before} sizes={b.columns === 1 ? undefined : "(min-width: 768px) 50vw, 100vw"} {...q} /> }}
                right={{ label: p.after.label, render: (q) => <Picture img={p.after} sizes={b.columns === 1 ? undefined : "(min-width: 768px) 50vw, 100vw"} {...q} /> }}
              />
              {p.caption && <figcaption className="mt-1.5 text-hint text-muted-foreground"><Inline text={p.caption} /></figcaption>}
            </figure>
          ))}
        </div>
      );
    case "mosaic":
      return (
        <Mosaic
          size={b.size}
          lead={b.lead}
          images={b.images.map((i) => ({ id: i.src, title: (i.caption ?? "").replace(/\*\*|`/g, ""), thumb: i.thumb, full: i.full, w: i.w, h: i.h, fw: i.fw }))}
        />
      );
    case "steps":
      return (
        <ol className="card-grid card-min-200 gap-2.5">
          {b.steps.map((s, i) => (
            <li key={i} className="flex min-w-0 gap-2.5 rounded-xl border border-border bg-card p-3">
              <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-brand text-tag font-semibold text-on-brand">{i + 1}</span>
              <div className="min-w-0">
                <div className="text-subhead font-semibold">{s.title}</div>
                <div className="text-dense text-muted-foreground"><Inline text={s.text} /></div>
              </div>
            </li>
          ))}
        </ol>
      );
    case "facts":
      return (
        <dl className="card-grid card-min-160 gap-2.5">
          {b.facts.map((f, i) => (
            <div key={i} className="min-w-0 rounded-xl border border-border bg-card p-3">
              <dd className="text-2xl leading-tight font-semibold tracking-tight wrap-anywhere">{f.value}</dd>
              <dt className="text-dense">{f.label}</dt>
              {f.note && <p className="mt-0.5 text-hint text-muted-foreground"><Inline text={f.note} /></p>}
            </div>
          ))}
        </dl>
      );
    case "bars":
      return (
        <BarChart
          title={b.title}
          series={b.series}
          rows={b.rows.map((r) => ({ ...r, key: slugify(r.label) || r.label }))}
          mode={b.mode}
          unit={b.unit}
          digits={b.digits}
          rowHeader={b.rowHeader}
          footer={b.footer && <Inline text={b.footer} />}
        />
      );
    case "deltas":
      return (
        <DeltaChart
          title={b.title}
          rows={b.rows.map((r) => ({ ...r, key: slugify(r.label) || r.label }))}
          better={b.better}
          labels={b.labels}
          unit={b.unit}
          digits={b.digits}
          rowHeader={b.rowHeader}
          footer={b.footer && <Inline text={b.footer} />}
        />
      );
    case "table":
      return (
        <figure className="m-0 min-w-0">
          <div className="max-w-full overflow-x-auto rounded-xl border border-border bg-card">
            <table className="w-full text-dense tabular-nums">
              <thead>
                <tr className="border-b border-border text-left text-hint text-muted-foreground">
                  {b.head.map((h, i) => <th key={i} className="px-2.5 py-1.5 font-medium whitespace-nowrap">{h}</th>)}
                </tr>
              </thead>
              <tbody>
                {b.rows.map((r, i) => (
                  <tr key={i} className="border-b border-border/60 last:border-0">
                    {r.map((c, k) => <td key={k} className="px-2.5 py-1 align-top"><Inline text={c} /></td>)}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {b.caption && <figcaption className="mt-1.5 text-hint text-muted-foreground"><Inline text={b.caption} /></figcaption>}
        </figure>
      );
    case "sources":
      return (
        <p className="text-hint text-muted-foreground">
          Sources: {b.items.map((s, i) => <span key={i}>{i > 0 && " · "}<Inline text={s} /></span>)}
        </p>
      );
  }
}

/** All blocks of a chapter, spaced. */
export function StoryBlocks({ blocks }: { blocks: ResolvedBlock[] }) {
  return <div className="flex flex-col gap-3.5">{blocks.map((b, i) => <StoryBlock key={i} block={b} />)}</div>;
}
