// A filterable, sortable, groupable list: count line, FilterBar, then the rows (or grouped rows), or the empty note.
// Rendering of one item and the item container's layout are up to the caller (rows, a grid ...). FilterableList
// owns its list state; ListView renders a state the caller holds (useListState), with room for extra controls and a
// body of its own (ImageBrowser's matrix).
import { Fragment, type ReactNode } from "react";
import { FilterBar } from "./FilterBar";
import { useListState, type ListApi, type ListConfig } from "./use-list-state";

interface ViewProps<T> {
  config: ListConfig<T>;
  renderItem: (item: T) => ReactNode;
  itemKey: (item: T) => string;
  /** plural noun for the count: "pages", "images" */
  noun: string;
  /** container classes for the items, e.g. "grid grid-cols-3 gap-2" (default: a column of rows) */
  layout?: string;
  empty?: string;
  /** optional header left of the count */
  header?: ReactNode;
  /** controls under the FilterBar (view toggles, sizes) */
  toolbar?: ReactNode;
  /** replaces the rows when set (the empty note still comes first) */
  body?: ReactNode;
}

export function FilterableList<T>({ items, ...props }: ViewProps<T> & { items: T[] }) {
  const list = useListState(items, props.config);
  return <ListView list={list} {...props} />;
}

export function ListView<T>({ list, config, renderItem, itemKey, noun, layout = "flex flex-col gap-1.5", empty = "Nothing matches.", header, toolbar, body }: ViewProps<T> & { list: ListApi<T> }) {
  const { results, groups, total } = list;
  const rows = (items: T[]) => <div className={layout}>{items.map((it) => <Fragment key={itemKey(it)}>{renderItem(it)}</Fragment>)}</div>;
  return (
    <div className="min-w-0">
      <div className="mb-2 flex items-start justify-between gap-3">
        <div className="min-w-0">{header}</div>
        <span className="shrink-0 pt-1 text-hint whitespace-nowrap text-muted-foreground tabular-nums">
          {results.length === total ? `${total} ${noun}` : `${results.length} of ${total} ${noun}`}
        </span>
      </div>
      <FilterBar config={config} list={list} />
      {toolbar}
      {results.length === 0 ? (
        <p className="py-3 text-dense text-muted-foreground">{empty}</p>
      ) : body ? (
        body
      ) : groups ? (
        <div className="flex flex-col gap-4">
          {groups.map((g) => (
            <section key={g.key}>
              <GroupHeading>{g.title}</GroupHeading>
              {rows(g.items)}
            </section>
          ))}
        </div>
      ) : (
        rows(results)
      )}
    </div>
  );
}

/** Heading of a group of items. */
export const GroupHeading = ({ children }: { children: ReactNode }) => (
  <h3 className="mb-1.5 text-xs tracking-[0.06em] text-muted-foreground uppercase">{children}</h3>
);
