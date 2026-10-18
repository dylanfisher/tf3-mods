// Island for the run-compare section page: comparisons with search, seed and kind filters, sort, group by seed.
import { FilterableList, type ListConfig } from "@/components/site/filters";
import TitleArt from "@/components/site/TitleArt";
import { CHIP_CLIP, chipClass } from "@/lib/chip";
import type { EntryCounts } from "./types";

export interface ListEntry {
  slug: string;
  href: string;
  title: string;
  seed: string;
  /** "YYYY-MM-DD" of built */
  date: string;
  built: string;
  single: boolean;
  /** worded counts (load.ts), so the list and the page header say the same */
  counts: EntryCounts;
  thumb?: string;
  runs: { label: string; kind: string; session: string; load: string }[];
}

interface Props {
  entries: ListEntry[];
  /** run kinds: chip look and a "With a <label> <run>" filter */
  kinds: { value: string; label: string; outline: boolean }[];
  /** what a run is called (RunCompareSource.runName) */
  runName: { one: string; many: string };
  storageKey: string;
}

/** Newest first: by build time, then by data folder (slug). */
const newest = (a: ListEntry, b: ListEntry) => b.built.localeCompare(a.built) || b.slug.localeCompare(a.slug);
const seedOf = (e: ListEntry) => e.seed || "-";

export default function CompareList({ entries, kinds, runName, storageKey }: Props) {
  const outline = new Set(kinds.filter((k) => k.outline).map((k) => k.value));
  const config: ListConfig<ListEntry> = {
    storageKey,
    search: {
      placeholder: `Search title, ${runName.one} label, session`,
      text: (e) => [e.title, e.seed, e.slug, ...e.runs.map((r) => `${r.label} ${r.session}`)].join(" "),
    },
    selects: [
      {
        id: "seed", label: "Seed", allLabel: "All seeds",
        options: (items) => {
          const n = new Map<string, number>();
          for (const e of items) n.set(seedOf(e), (n.get(seedOf(e)) ?? 0) + 1);
          return [...n.keys()].sort().map((k) => ({ value: k, label: `Seed ${k} (${n.get(k)})` }));
        },
        test: (e, v) => seedOf(e) === v,
      },
      {
        id: "kind", label: "Kind", allLabel: "All kinds",
        options: [
          { value: "multi", label: `Several ${runName.many}` },
          { value: "single", label: `Single ${runName.one}` },
          ...kinds.filter((k) => outline.has(k.value)).map((k) => ({ value: `has:${k.value}`, label: `With a ${k.label} ${runName.one}` })),
        ],
        test: (e, v) =>
          v === "multi" ? e.runs.length >= 2 : v === "single" ? e.single : v.startsWith("has:") ? e.runs.some((r) => r.kind === v.slice(4)) : true,
      },
    ],
    sorts: [
      { value: "new", label: "Newest first", compare: newest },
      { value: "old", label: "Oldest first", compare: (a, b) => -newest(a, b) },
      { value: "seed", label: "By seed", compare: (a, b) => (a.seed || "").localeCompare(b.seed || "") || newest(a, b) },
      { value: "runs", label: "Most runs", compare: (a, b) => b.runs.length - a.runs.length || newest(a, b) },
    ],
    group: { label: "Group by seed", choices: [{ value: "seed", label: "Seed", key: seedOf, title: (k, n) => `Seed ${k} · ${n}` }] },
  };
  return (
    <FilterableList
      items={entries}
      config={config}
      noun="comparisons"
      itemKey={(e) => e.slug}
      empty="No comparison matches."
      renderItem={(e) => {
        const c = e.counts;
        return (
          <a
            href={e.href}
            className="grid min-w-0 grid-cols-[64px_1fr] items-center gap-x-3 gap-y-1 rounded-lg border border-border bg-card p-2 transition-colors hover:border-brand focus-visible:border-brand sm:grid-cols-[96px_1fr_auto]"
          >
            {e.thumb ? (
              <img src={e.thumb} alt="" loading="lazy" decoding="async" className="aspect-[8/5] w-full rounded-md bg-chip object-cover sm:row-span-1" />
            ) : (
              <TitleArt title={e.title} aspect={8 / 5} className="aspect-[8/5] rounded-md" />
            )}
            <span className="min-w-0">
              <span className="block truncate font-semibold text-brand-text">{e.title}</span>
              <span className="mt-1 flex flex-wrap gap-1">
                <span className={chipClass("brand", CHIP_CLIP)}>{e.seed || "-"}</span>
                {e.runs.map((r, i) => (
                  <span key={i} className={chipClass(outline.has(r.kind) ? "outline" : "default", CHIP_CLIP)} title={`${r.session}:${r.load}`}>{r.label}</span>
                ))}
              </span>
            </span>
            <span className="col-start-2 text-meta whitespace-nowrap text-muted-foreground tabular-nums sm:col-start-auto sm:text-right">
              <b className="font-semibold text-foreground">{c.runs.value} {c.runs.label}</b>
              <span className="sm:hidden"> · </span>
              <br className="hidden sm:inline" />
              {c.units.value} {c.units.label}{c.units.extra ? ` +${c.units.extra}` : ""}
              {c.years != null ? ` · ${c.years} y` : ""}
              <span className="sm:hidden"> · </span>
              <br className="hidden sm:inline" />
              {e.date}
            </span>
          </a>
        );
      }}
    />
  );
}
