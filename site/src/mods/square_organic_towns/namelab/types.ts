// Shapes of the Name lab's data (plans/square_organic_towns/names/data.json, export_names.py) and of its state.
// Only the fields the page reads are typed; the generator (gen.ts) reads the rest.
/* eslint-disable @typescript-eslint/no-explicit-any */

export interface MapTown {
  id: string | number;
  old: string;
  new: string;
  parts: (string | null)[];
  feature?: string;
  tags: [string, number][];
  river?: string;
  lake?: string;
  read?: string;
  dialect?: string;
  score?: number;
  character?: boolean;
}

export interface NameData {
  built: string;
  src: Record<string, { sha: string; mtime: string }>;
  pn: { TAGS: string[]; SPECIES: string[]; SPEC: Record<string, number>; LANGS: string[]; consts: Record<string, number>; [k: string]: any };
  lang: Record<string, { spec?: string; gen?: string; affix?: string; [k: string]: any }>;
  towns: Record<string, { names?: string[]; sources?: string[] }>;
  stop?: { LANG?: Record<string, Record<string, any>>; THEMES?: any };
  presets: Record<string, Record<string, number>>;
  map?: {
    towns: MapTown[];
    summary?: { gen?: string; list?: string; rivers?: string; lakes?: string };
    seedText?: string;
    session?: string;
    log?: string;
  } | null;
  [k: string]: any;
}

export interface RatedName {
  key: string;
  name: string;
  mode: string;
  lang: string;
  parts: string[];
  site: string[];
  character: boolean;
  r?: number;
}

export interface LabState {
  v: 1;
  lang: string;
  climate: string;
  /** naming rules (NEXT_PHASE_BRIEF 60 / 61): "s61" evocative names, kinds and industry cues, "s60" descriptive first,
   * "s53" the naming review's */
  rules?: "s61" | "s60" | "s53";
  mode: "morph" | "remix" | "desc" | "feat" | "old";
  view: "grid" | "all";
  seed: number;
  dialect: string;
  affixP: number;
  character: boolean;
  shared: boolean;
  budget: boolean;
  preset: string | null;
  site: Record<string, number>;
  consts: Record<string, number>;
  spec: Record<string, number>;
  edits: Record<string, Partial<Record<"spec" | "gen" | "affix", string>>>;
  ideas: Record<string, Partial<Record<"adj" | "old" | "oldGroups", string>>>;
  opt: { order: number; bias: number; singleWords: boolean; oldShare: number; spelling: boolean; count: number };
  ratings: Record<string, RatedName>;
  pinned: Record<string, RatedName>;
  notes: string;
  tab: string;
  listKind: "spec" | "gen" | "affix";
  listFilter: string;
  listSort: "fit" | "file";
}
