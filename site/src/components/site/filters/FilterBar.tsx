// The controls for useListState: search, select filters, toggles, sort, group. Shared labelled widgets (../fields).
import { Input } from "@/components/ui/input";
import { LabeledCheckbox, LabeledSelect } from "../fields";
import type { ListApi, ListConfig } from "./use-list-state";

/** The grouping control: a checkbox for one choice, a "Group by" select (with "None") for several. */
export function GroupControl<T>({ config, list }: { config: ListConfig<T>; list: ListApi<T> }) {
  const g = config.group;
  if (!g || !g.choices.length) return null;
  if (g.choices.length === 1)
    return <LabeledCheckbox label={g.label} checked={list.state.group !== ""} onChange={(v) => list.set.group(v ? g.choices[0].value : "")} />;
  return (
    <LabeledSelect
      label={g.label}
      value={list.state.group}
      options={[{ value: "", label: "None" }, ...g.choices.map(({ value, label }) => ({ value, label }))]}
      onChange={list.set.group}
    />
  );
}

export function FilterBar<T>({ config, list }: { config: ListConfig<T>; list: ListApi<T> }) {
  const { state, set, options } = list;
  return (
    <div className="mb-3 flex flex-wrap items-center gap-2">
      {config.search && (
        <Input
          type="search"
          value={state.q}
          onChange={(e) => set.q(e.currentTarget.value)}
          placeholder={config.search.placeholder}
          aria-label={config.search.placeholder}
          className="min-w-0 flex-[1_1_240px] bg-background"
        />
      )}
      {config.selects?.map((s) => (
        <LabeledSelect
          key={s.id}
          label={s.label}
          hideLabel
          value={state.selects[s.id] ?? ""}
          options={[{ value: "", label: s.allLabel }, ...(options[s.id] ?? [])]}
          onChange={(v) => set.select(s.id, v)}
        />
      ))}
      {config.sorts && config.sorts.length > 1 && (
        <LabeledSelect label="Sort" hideLabel value={state.sort} options={config.sorts.map(({ value, label }) => ({ value, label }))} onChange={set.sort} />
      )}
      {config.toggles?.map((t) => (
        <LabeledCheckbox key={t.id} label={t.label} checked={!!state.toggles[t.id]} onChange={(v) => set.toggle(t.id, v)} />
      ))}
      {config.group?.inFilterBar !== false && <GroupControl config={config} list={list} />}
    </div>
  );
}
