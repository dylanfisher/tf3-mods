// Generic kind "image-grid": every image of the section in a filterable grid. Types of the manifest source and of the
// island's data. Only erasable TypeScript (manifests import the source type through sections/define.ts).

/** A facet of the images (style, terrain ...): a filter and a "Group by" choice. */
export interface Facet {
  key: string;
  label: string;
  /** values in display order, with their labels */
  values: { value: string; label: string }[];
}

export type ThumbSize = "s" | "m" | "l";

/** The section's `source` (all optional). */
export type ImageGridSource = {
  /**
   * Repo-relative JSON describing the images: { facets: Facet[], items: [{ file, title?, <facet>: value }] } (file
   * relative to the manifest's folder, "../" allowed). A builder writes it next to its images (e.g. tools/ot_preview.py ->
   * svg/previews.json). Without one, the images' folders are the only facet.
   */
  manifest?: string;
  /** facets overriding the manifest's */
  facets?: Facet[];
  /** facet key the grid is grouped by at first (the visitor can change it) */
  groupBy?: string;
  /** offers a rows x columns matrix view (e.g. style x terrain) */
  matrix?: { rows: string; cols: string };
  /** first thumbnail size (default "m") */
  size?: ThumbSize;
  /** first view: "grid" (default), "wall" (justified rows, no captions until hover) or "matrix" (needs `matrix`) */
  view?: GridView;
};

export type GridView = "grid" | "wall" | "matrix";

/** The builder's manifest file (source.manifest). */
export interface ImageManifest {
  facets?: Facet[];
  items?: ({ file: string; title?: string } & Record<string, string>)[];
}

export interface BrowserImage {
  id: string;
  name: string;
  /** caption (the manifest's title, else the file name) */
  title: string;
  folder: string;
  /** manifest order (images without an entry come after, in path order) */
  order: number;
  /** facet key -> value ("folder" is always set) */
  facets: Record<string, string>;
  thumb: string;
  full: string;
  /** thumb width / height */
  w: number;
  h: number;
  /** full width (srcset) */
  fw: number;
}

export interface ImageGridOptions {
  facets: Facet[];
  groupBy?: string;
  matrix?: { rows: string; cols: string };
  size?: ThumbSize;
  view?: GridView;
}
