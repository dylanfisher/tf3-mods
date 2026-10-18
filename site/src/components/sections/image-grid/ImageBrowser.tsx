// Island for the "image-grid" kind: thumbnails with search, a filter per facet, group by a facet, a Wall view (justified
// rows, components/site/Mosaic), an optional rows x columns matrix (one per group when grouped), three thumbnail sizes
// and the site lightbox (lib/lightbox.ts; previous / next step through the images shown, in page order).
// The list (filters, sort, grouping, count, empty note) is the shared list toolkit (components/site/filters).
import { useMemo } from "react";
import { LabeledSelect } from "@/components/site/fields";
import { GroupControl, GroupHeading, ListView, useListState, type ListConfig } from "@/components/site/filters";
import Mosaic from "@/components/site/Mosaic";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { humanName } from "@/lib/format";
import { lightboxAttrs, lightboxGroup } from "@/lib/lightbox";
import { asRecord } from "@/lib/storage";
import { usePersistentState } from "@/lib/use-persistent-state";
import { cn } from "@/lib/utils";
import type { BrowserImage, GridView as View, ImageGridOptions, ThumbSize as Size } from "./types";

const GRID: Record<Size, string> = {
  s: "grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-6",
  m: "grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4",
  l: "grid grid-cols-1 gap-3 sm:grid-cols-2",
};
const CELL_W: Record<Size, string> = { s: "w-28", m: "w-44", l: "w-72" };
/** what a thumb is shown at, for srcset: grid columns per size, the matrix cell widths */
const GRID_SIZES: Record<Size, string> = {
  s: "(min-width: 1024px) 190px, (min-width: 640px) 25vw, 33vw",
  m: "(min-width: 1024px) 280px, (min-width: 640px) 33vw, 50vw",
  l: "(min-width: 640px) 50vw, 100vw",
};
const CELL_SIZES: Record<Size, string> = { s: "112px", m: "176px", l: "288px" };

export default function ImageBrowser({ images, storageKey, options }: { images: BrowserImage[]; storageKey: string; options?: ImageGridOptions }) {
  const facets = options?.facets ?? [];
  const facetOf = useMemo(() => Object.fromEntries(facets.map((f) => [f.key, f])), [facets]);
  const label = (key: string, v: string | undefined) => (v == null ? "-" : facetOf[key]?.values.find((x) => x.value === v)?.label ?? v);

  const config = useMemo<ListConfig<BrowserImage>>(() => ({
    storageKey,
    search: { placeholder: "Search", text: (i) => `${i.title} ${i.folder} ${i.name}` },
    selects: facets.map((f) => ({
      id: f.key, label: f.label, allLabel: `All: ${f.label.toLowerCase()}`,
      options: (items: BrowserImage[]) => f.values
        .map((v) => ({ value: v.value, label: `${v.label} (${items.filter((i) => i.facets[f.key] === v.value).length})` }))
        .filter((o) => !o.label.endsWith("(0)")),
      test: (i: BrowserImage, v: string) => i.facets[f.key] === v,
    })),
    sorts: [
      { value: "order", label: "Default order", compare: (a, b) => a.order - b.order || a.id.localeCompare(b.id, "en", { numeric: true }) },
      { value: "name", label: "By name", compare: (a, b) => humanName(a.title).localeCompare(humanName(b.title)) },
    ],
    group: {
      label: "Group by",
      initial: options?.groupBy,
      inFilterBar: false,
      choices: facets.map((f) => {
        const order = f.values.map((v) => v.value);
        const rank = (k: string) => { const i = order.indexOf(k); return i < 0 ? 1e9 : i; };
        return {
          value: f.key,
          label: f.label,
          key: (i: BrowserImage) => i.facets[f.key] ?? "",
          title: (k: string, n: number) => `${k ? label(f.key, k) : "Other"} · ${n}`,
          compare: (a: string, b: string) => rank(a) - rank(b),
        };
      }),
    },
  }), [storageKey, facets]); // eslint-disable-line react-hooks/exhaustive-deps
  const list = useListState(images, config);
  const { results } = list;

  // view and size: per list, restored after mount (the server render uses the defaults)
  const firstView: View = options?.view === "matrix" && !options?.matrix ? "grid" : options?.view ?? "grid";
  const [vs, setVs] = usePersistentState<{ view: View; size: Size }>(`${storageKey}:view`, { view: firstView, size: options?.size ?? "m" }, (raw, d) => {
    const s = asRecord(raw);
    return {
      view: s.view === "grid" || s.view === "wall" || (s.view === "matrix" && options?.matrix) ? (s.view as View) : d.view,
      size: typeof s.size === "string" && s.size in GRID ? (s.size as Size) : d.size,
    };
  });
  const { view, size } = vs;
  const setView = (v: View) => setVs((s) => ({ ...s, view: v }));
  const setSize = (v: Size) => setVs((s) => ({ ...s, size: v }));

  // grid and wall show the groups; the matrix shows one table per group (each with only its own rows and columns)
  const groups = list.groups;

  const matrices = useMemo(() => {
    const m = options?.matrix;
    if (view !== "matrix" || !m || !facetOf[m.rows] || !facetOf[m.cols]) return null;
    const build = (items: BrowserImage[], title?: string, key = "all") => {
      const present = (k: string) => facetOf[k].values.map((v) => v.value).filter((v) => items.some((i) => i.facets[k] === v));
      const rows = present(m.rows), cols = present(m.cols);
      const cell = (r: string, c: string) => items.filter((i) => i.facets[m.rows] === r && i.facets[m.cols] === c);
      const rest = items.filter((i) => !i.facets[m.rows] || !i.facets[m.cols]);
      return { key, title, rows, cols, cell, rest };
    };
    return groups ? groups.map((g) => build(g.items, g.title, g.key)) : [build(results)];
  }, [results, groups, view, options?.matrix, facetOf]);

  // plain render functions (not components), so a re-render keeps the <img> elements
  const thumb = (i: BrowserImage, caption = true, sizes = GRID_SIZES[size]) => (
    <button
      key={i.id}
      type="button"
      {...lightboxAttrs({ src: i.full, title: i.title })}
      className="group block w-full min-w-0 overflow-hidden rounded-lg border border-border bg-card text-left hover:border-brand focus-visible:border-brand"
      title={i.title}
    >
      <img
        src={i.thumb}
        srcSet={i.fw > i.w ? `${i.thumb} ${i.w}w, ${i.full} ${i.fw}w` : undefined}
        sizes={sizes}
        width={i.w}
        height={i.h}
        alt={i.title}
        loading="lazy"
        decoding="async"
        className="h-auto w-full bg-chip"
      />
      {caption && <span className="block truncate px-2 py-1 text-tag text-muted-foreground">{i.title}</span>}
    </button>
  );
  const grid = (items: BrowserImage[]) => <div className={GRID[size]}>{items.map((i) => thumb(i))}</div>;
  const wall = (items: BrowserImage[]) => <Mosaic images={items} size={size} />;
  const views: { value: View; label: string }[] = [
    { value: "grid", label: "Grid" },
    { value: "wall", label: "Wall" },
    ...(options?.matrix && facetOf[options.matrix.rows] && facetOf[options.matrix.cols]
      ? [{ value: "matrix" as View, label: `${facetOf[options.matrix.rows].label} × ${facetOf[options.matrix.cols].label}` }]
      : []),
  ];

  const toolbar = (
    <div className="mb-3 flex flex-wrap items-center gap-x-3 gap-y-2">
      <ToggleGroup aria-label="View" variant="outline" size="sm" spacing={0} value={[view]} onValueChange={(v) => { const x = (v as string[])[0]; if (x) setView(x as View); }}>
        {views.map((v) => (
          <ToggleGroupItem key={v.value} value={v.value} className="data-[pressed]:bg-primary data-[pressed]:text-primary-foreground">{v.label}</ToggleGroupItem>
        ))}
      </ToggleGroup>
      <GroupControl config={config} list={list} />
      <LabeledSelect label="Size" value={size} options={[{ value: "s", label: "Small" }, { value: "m", label: "Medium" }, { value: "l", label: "Large" }]} onChange={(v) => setSize(v as Size)} />
    </div>
  );

  const matrixTable = (mx: NonNullable<typeof matrices>[number]) => (
    <div className="overflow-x-auto rounded-lg border border-border">
      <table className="border-collapse text-hint">
        <thead>
          <tr>
            <th className="sticky left-0 z-10 border-b border-border bg-background p-1.5" />
            {mx.cols.map((c) => <th key={c} className="border-b border-border p-1.5 text-left font-semibold text-muted-foreground">{label(options!.matrix!.cols, c)}</th>)}
          </tr>
        </thead>
        <tbody>
          {mx.rows.map((r) => (
            <tr key={r}>
              <th className="sticky left-0 z-10 border-b border-border bg-background p-1.5 text-left align-top font-semibold whitespace-nowrap text-muted-foreground">{label(options!.matrix!.rows, r)}</th>
              {mx.cols.map((c) => {
                const items = mx.cell(r, c);
                return (
                  <td key={c} className="border-b border-border p-1.5 align-top">
                    <div className={cn("flex flex-col gap-1.5", CELL_W[size])}>
                      {items.map((i) => thumb(i, items.length > 1, CELL_SIZES[size]))}
                    </div>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
  const matrixBody = matrices && (
    <div className="flex flex-col gap-6">
      {matrices.map((mx) => (
        <section key={mx.key} className="flex min-w-0 flex-col gap-2">
          {mx.title && <GroupHeading>{mx.title}</GroupHeading>}
          {matrixTable(mx)}
          {mx.rest.length > 0 && (
            <>
              <GroupHeading>Not in the matrix · {mx.rest.length}</GroupHeading>
              {grid(mx.rest)}
            </>
          )}
        </section>
      ))}
    </div>
  );
  const wallBody = view === "wall" && (
    groups ? (
      <div className="flex flex-col gap-6">
        {groups.map((g) => (
          <section key={g.key} className="flex min-w-0 flex-col gap-2">
            <GroupHeading>{g.title}</GroupHeading>
            {wall(g.items)}
          </section>
        ))}
      </div>
    ) : wall(results)
  );

  return (
    <div className="min-w-0" {...lightboxGroup}>
      <ListView
        list={list}
        config={config}
        noun="images"
        layout={GRID[size]}
        itemKey={(i) => i.id}
        renderItem={(i) => thumb(i)}
        toolbar={toolbar}
        body={matrixBody || wallBody || undefined}
      />

    </div>
  );
}
