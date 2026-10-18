// Kind "story", timeline and list layouts (React island): search, a tag filter, newest / oldest first and, on the
// timeline, grouping by month; list entries open to their blocks. Built on the shared list toolkit.
import { useMemo, useState } from "react";
import { GroupHeading, ListView, useListState, type ListConfig } from "@/components/site/filters";
import Inline from "@/components/site/Inline";
import { chipClass } from "@/lib/chip";
import { cn } from "@/lib/utils";
import type { ResolvedChapter } from "./model";
import { StoryBlocks } from "./StoryBlocks";

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const month = (d?: string) => (d ? `${MONTHS[Number(d.slice(5, 7)) - 1]} ${d.slice(0, 4)}` : "Undated");
const day = (d: string) => `${MONTHS[Number(d.slice(5, 7)) - 1].slice(0, 3)} ${Number(d.slice(8, 10))}`;

export default function StoryList({ chapters, tags, layout, storageKey }: {
  chapters: ResolvedChapter[];
  tags: { key: string; label: string }[];
  layout: "timeline" | "list";
  storageKey: string;
}) {
  const label = (k: string) => tags.find((t) => t.key === k)?.label ?? k;
  const config = useMemo<ListConfig<ResolvedChapter>>(() => ({
    storageKey,
    search: { placeholder: "Search", text: (c) => c.text },
    selects: tags.length > 1 ? [{
      id: "tag",
      label: "Tag",
      allLabel: "All topics",
      options: (items) => tags.filter((t) => items.some((c) => c.tags?.includes(t.key))).map((t) => ({ value: t.key, label: `${t.label} (${items.filter((c) => c.tags?.includes(t.key)).length})` })),
      test: (c, v) => !!c.tags?.includes(v),
    }] : [],
    sorts: layout === "timeline"
      ? [
          { value: "old", label: "Oldest first", compare: (a, b) => (a.date ?? "").localeCompare(b.date ?? "") },
          { value: "new", label: "Newest first", compare: (a, b) => (b.date ?? "").localeCompare(a.date ?? "") },
        ]
      : undefined,
  }), [storageKey, tags, layout]);
  const list = useListState(chapters, config);
  const [open, setOpen] = useState<Record<string, boolean>>({});

  const chips = (c: ResolvedChapter) => c.tags?.map((t) => <span key={t} className={chipClass()}>{label(t)}</span>);

  if (layout === "list") {
    return (
      <ListView
        list={list}
        config={config}
        noun="entries"
        itemKey={(c) => c.id}
        layout="flex flex-col gap-2.5"
        renderItem={(c) => {
          const isOpen = !!open[c.id];
          return (
            <article id={c.id} className="scroll-mt-chrome-pad rounded-xl border border-border bg-card">
              <button
                type="button"
                aria-expanded={isOpen}
                onClick={() => setOpen((o) => ({ ...o, [c.id]: !isOpen }))}
                className="flex w-full items-start gap-3 rounded-xl p-4 text-left hover:bg-chip/60"
              >
                <span aria-hidden className={cn("mt-0.5 shrink-0 text-muted-foreground transition-transform", isOpen && "rotate-90")}>▸</span>
                <span className="flex min-w-0 flex-col gap-1">
                  <span className="font-semibold text-brand-text">{c.title}</span>
                  <span className="flex flex-wrap items-center gap-1.5 text-hint text-muted-foreground">
                    {c.date && <span className="tabular-nums">{c.date}</span>}
                    {chips(c)}
                  </span>
                  {c.summary && <span className="text-dense text-muted-foreground"><Inline text={c.summary} /></span>}
                </span>
              </button>
              {isOpen && c.blocks.length > 0 && <div className="border-t border-border px-4 pt-3.5 pb-4"><StoryBlocks blocks={c.blocks} /></div>}
            </article>
          );
        }}
        toolbar={
          <div className="mb-3 flex gap-2">
            <button type="button" className="text-hint text-brand-text hover:underline" onClick={() => setOpen(Object.fromEntries(list.results.map((c) => [c.id, true])))}>Open all</button>
            <span className="text-hint text-muted-foreground">·</span>
            <button type="button" className="text-hint text-brand-text hover:underline" onClick={() => setOpen({})}>Close all</button>
          </div>
        }
      />
    );
  }

  // Timeline: months as headings, a rail with one dot per entry.
  const months: { key: string; items: ResolvedChapter[] }[] = [];
  for (const c of list.results) {
    const k = month(c.date);
    const last = months.at(-1);
    if (last && last.key === k) last.items.push(c);
    else months.push({ key: k, items: [c] });
  }
  return (
    <ListView
      list={list}
      config={config}
      noun="entries"
      itemKey={(c) => c.id}
      renderItem={() => null}
      body={
        <div className="flex flex-col gap-6">
          {months.map((m) => (
            <section key={m.key}>
              <GroupHeading>{m.key}</GroupHeading>
              <ol className="relative ml-1 border-l border-border">
                {m.items.map((c) => (
                  <li key={c.id} id={c.id} className="relative scroll-mt-chrome-pad pb-7 pl-5 last:pb-1 sm:grid sm:grid-cols-[4.5rem_minmax(0,1fr)] sm:gap-3 sm:pl-4">
                    <span aria-hidden className="absolute top-1.5 -left-[5px] size-[9px] rounded-full bg-brand ring-2 ring-background" />
                    <div className="text-hint font-medium text-muted-foreground tabular-nums sm:pt-px">{c.date ? day(c.date) : ""}</div>
                    <div className="min-w-0">
                      <h3 className="font-semibold text-balance">{c.title}</h3>
                      {!!c.tags?.length && <div className="mt-1 flex flex-wrap gap-1.5">{chips(c)}</div>}
                      {c.summary && <p className="mt-1.5 max-w-[72ch] text-muted-foreground"><Inline text={c.summary} /></p>}
                      {c.blocks.length > 0 && <div className="mt-2.5"><StoryBlocks blocks={c.blocks} /></div>}
                    </div>
                  </li>
                ))}
              </ol>
            </section>
          ))}
        </div>
      }
    />
  );
}
