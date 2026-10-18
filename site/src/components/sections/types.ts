import type { SectionDef, Stat } from "@/lib/define-mod";
import type { ModInfo } from "@/lib/mods";

/** A manifest section after its kind checked the source (src/components/sections/resolve.ts): `source` is typed. */
export type Section<S = unknown> = Omit<SectionDef, "source"> & { source: S };

/** Props every section kind component receives. */
export interface SectionProps<S = unknown> {
  mod: ModInfo;
  section: Section<S>;
}

/**
 * One sub-page of a section, at /<mod-slug>/<section>/<slug>/ (e.g. one comparison of a comparison browser). A kind
 * declares its sub-pages through KindDef.items; the route src/pages/[mod]/[section]/[item].astro renders each with
 * KindDef.itemComponent.
 */
export interface SectionItem {
  /**
   * URL segment, unique within the section: lowercase letters, digits, "-" and ".", never "_". Build it with
   * slugify() from @/lib/slug from the item's data name (a folder like 2026-10-14_a-usa -> 2026-10-14-a-usa).
   */
  slug: string;
  title: string;
  /** plain text for the page header and the meta description */
  description?: string;
  /** facts for the page header (and for lists of items, if the kind shows them) */
  stats?: Stat[];
  /** list thumbnail URL */
  thumb?: string;
  /** whatever the item component needs (build time only, never sent to the client as a whole) */
  data?: unknown;
}

/** Props of a kind's item component. */
export interface ItemProps<S = unknown> extends SectionProps<S> {
  item: SectionItem;
}

/** An Astro or React component: Astro components and function components both fit. */
type Component<P> = (props: P) => unknown;

export interface KindDef<S = unknown> {
  /**
   * Checks the section's raw `source` and returns it typed (throw with `where` in the message: it names the mod and
   * section). Called once per section at build time; without it the kind gets the source as it is (unknown).
   */
  parseSource?: (raw: unknown, where: string) => S;
  /** Renders the section page body. */
  component: Component<SectionProps<S>>;
  /** Computed facts for the section card and page header, from the section's source/media. */
  summarize?: (p: SectionProps<S>) => Stat[];
  /** Card thumbnail URL for the section (e.g. its first image). */
  thumb?: (p: SectionProps<S>) => string | undefined;
  /** Badge on the section card, e.g. "Coming soon". */
  badge?: string;
  /**
   * Sub-pages of the section (build time, called once per route; cache inside if it reads files). Each becomes
   * /<mod-slug>/<section>/<item.slug>/, rendered by itemComponent. Link to them with itemHref() from @/lib/mods.
   */
  items?: (p: SectionProps<S>) => SectionItem[];
  /** Renders one sub-page body. Required with items. */
  itemComponent?: Component<ItemProps<S>>;
  /**
   * Data files the section publishes as they are, at /data/<mod-slug>/<section>/<name> (src/pages/data/...; link with
   * dataFileHref() from @/lib/mods): `name` a URL slug with its extension, `path` repo-relative. For islands that fetch
   * their data instead of carrying it in the page.
   */
  files?: (p: SectionProps<S>) => { name: string; path: string }[];
  /**
   * "On this page": anchors of the section page (ids of elements the kind renders), shown as a menu in the sticky page
   * tabs (SectionNav) instead of a sidebar. Build time.
   */
  toc?: (p: SectionProps<S>) => TocEntry[];
}

/** One anchor of a section page (KindDef.toc). */
export interface TocEntry { id: string; title: string }

/** A kind with its source type checked inside, so kinds of different source types share one registry. */
export const defineKind = <S>(k: KindDef<S>): AnyKind => k as AnyKind;

// The registry's erased view: parseSource is the gate between the raw manifest data and the typed kind.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type AnyKind = KindDef<any>;
