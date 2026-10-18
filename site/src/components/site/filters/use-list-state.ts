// Generic list state for browsers: search + select filters + toggles + sort + group, persisted per list
// (src/lib/use-persistent-state.ts; the search text is not kept). The config holds functions, so it is defined in the
// React component that uses it (an island gets only serializable data from Astro).
import { useMemo, useState } from "react";
import type { Option } from "@/components/site/fields";
import { asRecord } from "@/lib/storage";
import { usePersistentState } from "@/lib/use-persistent-state";


export interface SelectFilter<T> {
  id: string;
  /** accessible name, e.g. "Seed" */
  label: string;
  /** first option, value "" (no filter), e.g. "All seeds" */
  allLabel: string;
  /** options; a function derives them from the items (e.g. distinct seeds with counts) */
  options: Option[] | ((items: T[]) => Option[]);
  test: (item: T, value: string) => boolean;
}

export interface ToggleFilter<T> {
  id: string;
  label: string;
  /** items kept while the toggle is on */
  test: (item: T) => boolean;
}

export interface SortOption<T> {
  value: string;
  label: string;
  compare: (a: T, b: T) => number;
}

/** One way to group the list. */
interface GroupChoice<T> {
  value: string;
  /** option label in the "Group by" select (several choices) */
  label: string;
  key: (item: T) => string;
  /** group heading; default "<key> · <count>" */
  title?: (key: string, count: number) => string;
  /** group order; default: order of first appearance in the sorted list */
  compare?: (a: string, b: string) => number;
}

export interface GroupConfig<T> {
  /** one choice: the checkbox label ("Group by seed"); several: the select's label ("Group by", plus "None") */
  label: string;
  choices: GroupChoice<T>[];
  /** grouping before the visitor picks one (a choice value; default none) */
  initial?: string;
  /** false: the FilterBar leaves the group control out and the caller places <GroupControl> itself */
  inFilterBar?: boolean;
}

export interface ListConfig<T> {
  /** storage key (src/lib/storage.ts); unique per list, e.g. "<modId>/<section>/list" */
  storageKey: string;
  search?: { placeholder: string; text: (item: T) => string };
  selects?: SelectFilter<T>[];
  toggles?: ToggleFilter<T>[];
  sorts?: SortOption<T>[];
  group?: GroupConfig<T>;
}

/** The remembered part of the state. */
interface Kept {
  selects: Record<string, string>;
  toggles: Record<string, boolean>;
  sort: string;
  /** a group choice value, "" for none */
  group: string;
}

interface ListGroup<T> { key: string; title: string; items: T[] }

export function useListState<T>(items: T[], config: ListConfig<T>) {
  const defaults: Kept = {
    selects: Object.fromEntries((config.selects ?? []).map((s) => [s.id, ""])),
    toggles: Object.fromEntries((config.toggles ?? []).map((t) => [t.id, false])),
    sort: config.sorts?.[0]?.value ?? "",
    group: config.group?.initial ?? "",
  };
  const choices = config.group?.choices ?? [];
  const [kept, setKept] = usePersistentState<Kept>(config.storageKey, defaults, (raw, d) => {
    const s = asRecord(raw);
    // (older lists stored `group: true` for their one grouping)
    const group = s.group === true ? choices[0]?.value ?? "" : typeof s.group === "string" && (s.group === "" || choices.some((c) => c.value === s.group)) ? s.group : d.group;
    return {
      selects: { ...d.selects, ...(asRecord(s.selects) as Record<string, string>) },
      toggles: { ...d.toggles, ...(asRecord(s.toggles) as Record<string, boolean>) },
      sort: typeof s.sort === "string" && config.sorts?.some((o) => o.value === s.sort) ? s.sort : d.sort,
      group,
    };
  });
  const [q, setQ] = useState("");
  const state = { ...kept, q };

  const options = useMemo(
    () => Object.fromEntries((config.selects ?? []).map((s) => [s.id, typeof s.options === "function" ? s.options(items) : s.options])),
    [items, config.selects],
  );

  const results = useMemo(() => {
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const out = items.filter((it) => {
      for (const s of config.selects ?? []) {
        const v = kept.selects[s.id];
        if (v && options[s.id]?.some((o) => o.value === v) && !s.test(it, v)) return false;
      }
      for (const t of config.toggles ?? []) if (kept.toggles[t.id] && !t.test(it)) return false;
      if (words.length && config.search) {
        const hay = config.search.text(it).toLowerCase();
        if (!words.every((w) => hay.includes(w))) return false;
      }
      return true;
    });
    const sort = config.sorts?.find((o) => o.value === kept.sort);
    if (sort) out.sort(sort.compare);
    return out;
  }, [items, kept, q, config, options]);

  const groups = useMemo<ListGroup<T>[] | null>(() => {
    const g = choices.find((c) => c.value === kept.group);
    if (!g) return null;
    const by = new Map<string, T[]>();
    for (const it of results) {
      const k = g.key(it);
      if (!by.has(k)) by.set(k, []);
      by.get(k)!.push(it);
    }
    const keys = [...by.keys()];
    if (g.compare) keys.sort(g.compare);
    return keys.map((k) => ({ key: k, title: g.title ? g.title(k, by.get(k)!.length) : `${k} · ${by.get(k)!.length}`, items: by.get(k)! }));
  }, [results, kept.group, choices]);

  const set = {
    q: setQ,
    select: (id: string, v: string) => setKept((s) => ({ ...s, selects: { ...s.selects, [id]: v } })),
    toggle: (id: string, v: boolean) => setKept((s) => ({ ...s, toggles: { ...s.toggles, [id]: v } })),
    sort: (v: string) => setKept((s) => ({ ...s, sort: v })),
    group: (v: string) => setKept((s) => ({ ...s, group: v })),
  };

  return { state, set, options, results, groups, total: items.length };
}

export type ListApi<T> = ReturnType<typeof useListState<T>>;
