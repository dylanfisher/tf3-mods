# Mod microsites (tf3.dylanfisher.com)

Static site: one microsite per mod (player-facing landing + research pages), branded **square**. Astro (static)
+ React islands + MDX, Tailwind v4 (`src/styles/theme.css`, the only theme), shadcn/ui on Base UI
(`src/components/ui/`, generated). Plan and phases: `plans/site/PLAN.md`.

```
make site-dev      # dev server (http://localhost:4321)
make site-media    # manifest images -> public/media/ (WebP thumb + full per preset, cached in .cache/media.json)
make site-build    # pnpm run build: site-media + astro build -> dist/
make site-deploy   # build + push dist/ to the Pages repo (the user runs this; DRY_RUN=1 stages without pushing)
```

Node 23.6 or newer (`engines` in package.json): scripts/media.mjs and the Name lab's port check import the `.ts`
modules directly (type stripping). Checks: `pnpm --dir site astro check` (0 errors; the hints come from the faithful
`gen.ts` port) and `pnpm --dir site dlx knip@5` (unused files and exports; entries in `knip.json`).

## URLs: dashes, never underscores

Every URL the site makes is built from slugified segments (`src/lib/slug.ts`: `slugify`, `urlPath`): lowercase
letters, digits, `-` and `.`, never `_`. Mod ids and data folders keep their names; only the URLs change:
`square_organic_towns` -> `/square-organic-towns/`, comparison folder `2026-10-14_a-usa` ->
`/square-organic-towns/comparisons/2026-10-14-a-usa/`, media `plans/square_organic_towns/compare/2026-10-14_a-usa/...`
-> `/media/square-organic-towns/compare/2026-10-14-a-usa/...` (`mediaStem` in `src/lib/media-core.ts`), built assets
at `/assets/` (not `/_astro/`). Build hrefs with `mod.href`, `sectionHref`, `itemHref` (`src/lib/mods.ts`) or
`urlPath`, never by hand. The routes reject an underscore slug (`assertSlug`); section slugs in `defineMod` too.
Built file names are dashed too (base36 hashes, `_` in chunk names turned into `-`, astro.config.mjs). The deploy
fails when a built page links an internal URL with `_`. Hash links may carry data ids (`#view=all&a=<run id>`).

## Visitor state

Everything a page remembers goes through `src/lib/storage.ts`: keys `tf3-site:<modId>/<section>/<what>` (data names,
not URLs), JSON values, every access in try/catch. Islands use `usePersistentState(key, defaults, validate)`
(`src/lib/use-persistent-state.ts`): defaults on the server and first render, the stored value restored after mount
and passed through `validate`, every change saved. A renamed key keeps visitors' state with `migrateStore(new, old)`
(the Name lab moved from `ot-name-lab-v1`). The theme is the one exception: `localStorage("theme")`, read by
BaseLayout's inline head script before first paint; every change goes through `setTheme` (`src/lib/theme.ts`), which
ThemeToggle listens to.

## Adding a mod

1. `src/mods/<modId>/mod.ts`: `export default defineMod({ id, landing, highlights, sections })` (types and docs in
   `src/lib/define-mod.ts`). Name, summary, cover (`coverPath(id)`: `mods/<id>/_metadata/0.png`), tagline and accent
   (`branding/mods.js`) and the mod.io links (`branding/modio_state.json` / `modio_profiles.json`, whose `source` is
   also the footer's profile link, `getSiteProfile()`) are read, not repeated.
2. `src/mods/<modId>/landing.mdx`: short player-facing copy (American English). `highlights` (optional) puts big images
   above it: the first across the width, the rest as a mosaic (`components/site/Mosaic.tsx`), each opening in the
   lightbox with a link to its `section`. Lead with pictures: visual sections (showcase, walls, comparisons) first in
   `sections`, the written material (one "Behind the scenes" page, timeline, data) after them.
3. Sections: each has a `kind`. Generic kinds are in `src/components/sections/registry.ts` (`placeholder`,
   `image-grid`, `run-compare`, `data-explorer`, `story`); write them with the typed helpers in
   `src/components/sections/define.ts` (`runCompare({...})`, `imageGrid({...})`, `dataExplorer({...})`, `story({...})`,
   `placeholder({...})`), which type `source` for the kind. A mod-specific
   kind goes in `src/mods/<modId>/kinds.ts` (`export const kinds = { name: defineKind({ parseSource?, component,
   summarize?, thumb?, badge?, items?, itemComponent? }) }`) and is used as `kind: "<modId>/<name>"`. At build time
   `getSections(mod)` (`src/components/sections/resolve.ts`) runs each kind's `parseSource` once (an error names the
   mod and section) and the routes pass the checked section on: a kind component receives `{ mod, section }` with
   `section.source` typed (`SectionProps<S>`) and reads `section.media`. Data loaders fail loudly: `readJson` throws on a
   file that does not parse (naming it), a missing `source.dir` or a bad data file fails the build.
4. Images: list their repo-relative globs in a section's `media`, then `make site-media`. Pages look
   them up with `getMedia` / `getMediaGlob` (`src/lib/media.ts`). A glob may be a spec asking for a smaller preset or a
   center crop: `withPreset("grid", [globs])` or `{ glob, preset, crop: { zoom } }` (see Media below).
5. Card images: a section card shows `thumb: "<repo path>"` from the section when that image is built, else the kind's
   thumb (first image); without either it gets generated title art (`components/site/TitleArt.tsx`: the title fitted to
   the slot over brand-teal and mod-accent color fields). A mod without a cover gets the same art as its cover. The
   accent is `--mod-accent`, set once: by ModLayout around a mod's pages, by each home card for its mod; `bg-mod`
   (accent bars, brand teal without an accent) and `bg-mod-art` (title art, warm run-1 tone without one) read it.
6. `make site-build`, check the pages light/dark and at phone width.

## Page chrome (sticky)

The site header (`h-header`) and a mod's page tabs (`SectionNav`, full width, `h-subnav`) both stick to the top. Anything
else sticky on a mod page sits below them: `top-chrome` (flush, e.g. the comparison toolbar) or `top-chrome-pad` (with a
gap, e.g. the Name lab's site builder), with its max height reduced by the same; anchors use `scroll-mt-chrome-pad`.
No sidebars for page contents: a kind lists its anchors with `KindDef.toc` (story articles do) and the tabs show them as
an "On this page" menu at the end of the row.

## Sub-pages

A section kind can have pages of its own below the section, at `/<modId>/<section>/<item>/` (one comparison of a
comparison browser, one lab of a list ...). In the kind's `KindDef` (`src/components/sections/types.ts`):

- `items({ mod, section })` returns the sub-pages (`SectionItem`: `slug`, `title`, `description` (plain text),
  `stats`, `thumb`, and `data` for the item component, build time only). Called once per route at build time, so
  cache inside if it reads files.
- `itemComponent` renders one sub-page body; it receives `{ mod, section, item }`.
- `files({ mod, section })` (optional) publishes data files as they are at `/data/<mod-slug>/<section>/<name>`
  (`src/pages/data/[mod]/[section]/[file].ts`; `name` a slug with its extension, `path` repo-relative). Islands fetch
  them (`dataFileHref(mod, section, name)` from `src/lib/mods.ts`) instead of carrying big data in the page.

The generic route `src/pages/[mod]/[section]/[item].astro` builds every item of every such section (breadcrumb back
to the section, page header from the item's title, description and stats, the section's width). The section page
links to them with `itemHref(mod, section, item)` (`src/lib/mods.ts`). Item slugs: `slugify(<data name>)` (lowercase
letters, digits, `.`, `-`; an underscore fails the build).

## Run comparisons (`run-compare`)

Game runs compared unit by unit (towns, junctions ...). The section page lists every comparison (search, seed, kind,
sort, group by seed); each comparison is a sub-page with run cards, key points, a summary table (median [quartiles] or
sums, A / B ratio), the run table, a gallery (single-run pages), the unit viewer (pick A and B, side by side, slider,
all runs in a row, verdict filter, prev / next, keys ← → S X, `#view=all&unit=08&a=<run>&b=<run>` links; the older
`#town=` is still read) and the units a run created. Comparisons are dated and sorted by their data's `built`. Page order: `source.order`, default `"viewer-first"` (the unit viewer right under the page
header, on single-run pages the unit detail and the gallery; then run cards, key points, summary, run table, extra
units); `"details-first"` puts the cards and tables first.

- Data: a builder writes `<source.dir>/<page>/data.json` plus the shots (format: `RawCompare` version 3 in
  `src/components/sections/run-compare/types.ts`: `units`, `extraUnits`, `pairing`, `built`; version 2 with `towns` /
  `extraTowns` and HTML key notes is still read). Plain data, never HTML: hand-written key notes may use `**bold**`
  and `` `code` `` (rendered by `components/site/Inline.tsx`, nothing else). An unknown version fails the build.
  Declare the shots in the section's `media` glob.
- Labels, sentences and metrics: the section's `source` is a `RunCompareSource`: `dir`, the unit name (default the
  neutral `DEFAULT_UNIT`, "unit"), what a run is called (`runName`, default "run" / "runs"; Smart Lanes' bench says
  "twin"), run kinds, run cards, the page description (`describe`), generated key points
  (`autoNotes`; both get the data's `notes` too, so a builder can put structured results there for the source to word), the footer, summary rows (key, sum or quartiles, digits, scale), per-unit rows (cell formatters, ratio
  key), verdict categories, notes and gallery formatters, extra-unit columns. Formatters return inline markup, never
  HTML. Mod wording lives there, never in the kind. Examples: `src/mods/square_organic_towns/compare.ts` (towns of game
  runs), `src/mods/square_smart_lanes/bench.ts` (side-by-side test twins: runs = twin modes, units = test sets; the unit
  heading shows one name when every run names the unit the same).

## Image grids (`image-grid`)

Every image of the section's `media` in a grid: search, sizes, the site lightbox (← → between the images shown).
With a manifest the images get facets: `source.manifest` is a repo-relative JSON written by the builder next to its
images, `{ facets: [{ key, label, values: [{ value, label }] }], items: [{ file, title?, <facet>: value }] }` (file
relative to the manifest). Each facet becomes a filter and a "Group by" choice; `source.groupBy` picks the first
grouping and `source.matrix: { rows, cols }` adds a rows x columns view. Without a manifest the folders are the facet.
Views: Grid, Wall (justified rows, caption on hover: `components/site/Mosaic.tsx`) and the matrix; `source.view` picks the
first one. Grouped, the matrix shows one table per group, each with only its own rows and columns, so one manifest can
hold several sweeps (facets `row` / `col` shared, `sweep` the group). Thumbs carry `srcset` / `sizes` per view and size.
Examples: Organic Towns' street plans (`tools/ot_preview.py` -> `svg/previews.json`, style x terrain), Roundabouts'
layout wall (`plans/square_roundabouts/site/layouts.py`: 176 plan drawings from the mod's own geometry, 13 sweeps),
Smart Lanes' twins wall (`build_data.py` -> `twins.json`, junction x twin per bench run).

## Result tables (`data-explorer`)

Result tables (one row per probe call, test, run ...) as sub-pages: filters (one select per categorical column, the
first six shown, "More filters" for the rest; a search box over text columns), a breakdown chart (pass / fail share,
count or the median of a numeric column per value of one column; a click on a bar filters by it), and a sortable, paged
table; choices persist per table (`tf3-site:<modId>/<section>/<table>`). The section page shows the intro, a pass / fail
overview chart (one bar per table, linking to it) and the tables as cards by group.

- Data: `tools/site_table.py` turns CSVs into data files (version 1, column-oriented: `cat` columns dictionary-encoded,
  `num`, `text`; constant columns listed apart as "Same in every row"); builders with inputs of their own call its
  `table()` (e.g. `plans/square_roundabouts/site/build_data.py`). The kind publishes each file through `files()` and the
  island fetches it, so a 20,000-row table never sits in the page. An unknown version fails the build.
- Wording: the section's `source` is a `DataExplorerSource` (`data-explorer/types.ts`): `dir`, the row unit, the outcome
  column (`{ key, pass, passLabel, failLabel }`), column and value labels, groups, intro, and per table: title,
  description, notes (inline markup), first breakdown and measure, column order, hidden columns, and a unit or outcome
  of its own (search jobs: found / none found; such tables stay out of the overview chart). Example:
  `src/mods/square_roundabouts/probe.ts`.

## Written pages (`story`)

A page from typed blocks (`story/types.ts`): `p`, `list`, `parts` (labelled paragraphs: Symptom / Cause / Fix), `figure`,
`gallery`, `compare` (two images with the BeforeAfter slider), `pairs` (several sliders in a one- or two-column grid),
`mosaic` (a wall of images in justified rows with the lightbox; `lead` shows the first across the width,
`preset` its media preset, default "grid"), `steps` (a numbered flow), `facts` (number tiles), `bars`
(a BarChart), `deltas` (a DeltaChart: differences per pair that go either way; its rows written out or read at build
time from a data-explorer data file, `table: { file, value, groupBy, where?, only?, labels? }`, so measured numbers stay
in the builder's output), `table`, `sources`. Text is inline markup only. Three layouts: `article` (chapters with a sticky contents
list; only charts and sliders hydrate), `timeline` (dated entries on a rail by month, tag filter, oldest / newest first;
`changelog: { tag }` adds the mod's changelog, read from `description.html` by `src/lib/changelog.ts`), `list` (entries
that open to their blocks, tag filter, open / close all). The `story()` helper adds every image the blocks show to the
section's media with the preset each block needs (figures "default", galleries, sliders and pairs "view", mosaics their
own). Examples: `src/mods/square_roundabouts/showcase.ts` (mosaics and pairs), `behind-the-scenes.ts` (compact article),
`timeline.ts`; `src/mods/square_smart_lanes/showcase.ts` (pairs built from the builder's `showcase.json`, imported with
`with { type: "json" }`) and `results.ts` (deltas read from data files). No page uses the `list` layout right now.

## Charts and sliders

- `components/site/charts/BarChart.tsx`: horizontal bars (stacked for two series), share mode (pass / fail split, the
  first series' share at the tip) or value mode (totals), legend for two or more series, one tooltip per row (hover and
  keyboard focus), a Chart / Table toggle, rows as links (`href`) or buttons (`onSelect`). Plain-data props, so Astro
  pages hydrate it with `client:visible`. Colors: the theme's outcome pair `--chart-pass` (brand teal) / `--chart-fail`
  (orange), validated with the dataviz palette check (green / red fails it for color-blind readers, so charts never use
  `--up` / `--down`). Labels stay in text tokens.
- `components/site/charts/DeltaChart.tsx`: diverging rows for A minus B differences: a bar from zero to the row's mean
  (`--chart-pass` where the mean is better, `--chart-fail` where worse; `better: "higher" | "lower"`), one neutral dot per
  value, a shared symmetric scale, the mean and the "better" count at the tip, a tooltip per row, Chart / Table toggle.
  The side of zero and the signed number carry the meaning too, so color is never the only cue.
- `components/site/Mosaic.tsx`: justified rows of images (each at its own ratio, rows filled edge to edge, the last row
  not stretched), caption on hover (images never move on hover), optional `lead` image; used by the story block `mosaic`, the image grid's Wall
  view and the landing highlights. `components/site/Lightbox.tsx`: the one image viewer, mounted once in BaseLayout: the image on
  a blurred backdrop with title, n / total, ← → and an optional link to a page, no animation. Any clickable element
  opens it when it carries `lightboxAttrs({ src, title, href? })` (`src/lib/lightbox.ts`); previous / next walk the
  visible marked images of the closest `lightboxGroup` container (else the page). Used by the mosaic, the image grid,
  story figures and the comparison shots. Sliders (BeforeAfter) don't open it (dragging).
- `components/site/BeforeAfter.tsx`: two images of one view split by a draggable line (pointer or range input); the
  run-compare viewer's ShotSlider and story `compare` blocks use it.

## Mod-specific kinds

Organic Towns' Name lab (`src/mods/square_organic_towns/namelab/`, kind `square_organic_towns/name-lab`): a React
island (`client:only`) whose data file (`plans/square_organic_towns/names/data.json`; the path is written once, in
`namelab/data-file.ts`) is emitted as a hashed asset via `import.meta.glob(..., { query: "?url" })` and fetched on load,
so the page stays small. Visitor edits persist under `tf3-site:square_organic_towns/name-lab/state`; the generator is
plain TypeScript (`gen.ts`), checked against the mod's Lua by `node plans/square_organic_towns/names/check_port.mjs`.

Interactive lists reuse `src/components/site/filters/` (`useListState`, `FilterBar`, `FilterableList`, or `ListView`
over a state the island holds, with a `toolbar` and a custom `body`): search, selects, toggles, sort, grouping (one
choice: a checkbox; several: a "Group by" select), persisted per list. Labelled controls: `LabeledSelect` /
`LabeledCheckbox` (`components/site/fields.tsx`). Chips: `chipClass(tone)` (`src/lib/chip.ts`, tones default, brand,
warn, outline; `CHIP_CLIP` for long data text). Run colors: `src/lib/run-colors.ts`. Card grids: the `card-grid` /
`card-grid-fit` utilities (`card-min-<px>`).

## Theme and type scale

`src/styles/theme.css`: each palette token is declared once as `light-dark(<light>, <dark>)`; `color-scheme` is
"light dark" (system) on `:root` and forced by `data-theme`. Font sizes beside Tailwind's: `text-tag` (0.75rem),
`text-meta` (0.8), `text-hint` (0.84), `text-dense` (0.9), `text-subhead` (0.95), `text-lead` (1.05), `text-display`
(1.85); never `text-[...]`. A new step goes into theme.css and into `TEXT_SIZES` in `src/lib/utils.ts`, which registers
the names with `cn` (without that, `cn("text-hint text-muted-foreground")` would drop the size as a color).
Breaking anywhere: `wrap-anywhere`. Widths: `max-w-page`, `max-w-wide`, `max-w-shot`.

## shadcn components (site edits)

`src/components/ui/` is generated (`pnpm --dir site dlx shadcn@latest add <name>`); a re-add overwrites these edits,
so redo them: every file imports `cn` from `@/lib/utils` (the configured merger), not from `"cn"`; `button.tsx`'s
`link` variant uses `text-brand-text`; `toggle-group.tsx` holds `toggleVariants` (moved from the deleted, unused
`toggle.tsx`). Unused components are deleted, not kept.

## Media

`scripts/media.mjs`: effort, alpha quality, the SVG density and the size **presets** are `MEDIA_RECIPE` in
`src/lib/media-core.ts`: `default` (full 1600 px, thumb 480, quality 80: figures, landing highlights), `view` (1280 / 480,
q 72: side-by-side viewers, sliders), `grid` (1280 / 360, q 70: grids and walls with a lightbox), `wall` (1024 / 320, q 64:
walls of hundreds). A section's `media` entry is a glob (default preset) or a `MediaSpec` `{ glob, preset, crop }`
(`withPreset(preset, globs, crop?)` in `define-mod.ts`). A source declared by several sections is built once, with the
largest preset asked for; a `crop: { zoom, x?, y? }` (keep 1 / zoom of the frame around x, y, default the center) belongs
to the source, so every declaration gets it, and two different crops of one source fail the build. Use it for shots that
are mostly empty ground (Smart Lanes' bench shots). The cache (`.cache/media.json`) stores the recipe hash and each
entry's preset and crop, so a recipe change (or a `rev` bump after a code change in the script) reprocesses everything
once and a preset change reprocesses that source. A source that fails keeps its previous output and cache entry (the
run still exits 1). URLs come from `mediaUrl()`; the mod prefix of a source path from `stripModPrefix()`. Every `<img>`
of a grid, mosaic, story block or viewer has `loading="lazy"` (the lead image eager) and a thumb + full `srcset` with
`sizes` for where it shows.

Size on 2026-10-14: 909 sources, 118 MB of media (dist 128 MB), down from 717 sources and 167 MB (dist 181 MB) before the
presets.

## Hosting (one-time, by the user)

1. Create the public repo `dylanfisher/tf3-mods-site` (empty is fine).
2. `make site-deploy` (pushes `dist/` with `CNAME` and `.nojekyll` to `main`; the domain comes from `SITE_URL` in
   `astro.config.mjs`, its only source). `DRY_RUN=1` keeps the staged clone and prints its commit stat; while the remote
   does not exist yet it stages into a fresh local repo and shows git's error.
3. Repo Settings → Pages: Source "Deploy from a branch", branch `main`, folder `/ (root)`. Custom domain
   `tf3.dylanfisher.com`, then "Enforce HTTPS" once the certificate is issued.
4. DNS for dylanfisher.com: `CNAME` record `tf3` → `dylanfisher.github.io`. Optionally verify the domain in the
   GitHub account's Pages settings so no other account can claim it.
