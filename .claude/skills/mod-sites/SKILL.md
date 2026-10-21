---
name: mod-sites
description: >-
  Mod microsites on tf3.dylanfisher.com (site/, Astro + React + Tailwind v4 + shadcn on Base UI): adding a mod's landing and research pages, section kinds (run-compare, image-grid, data-explorer, story, mod-specific), the WebP media build, builders that emit data, deploy. Use when creating or changing a mod's demo/showcase page, porting a generated HTML page into the site, or deploying the site.
---

# Mod microsites (square)

One static site, one microsite per mod: a short player-facing **landing** (`/<modId>/`) and a **research index**
of the behind-the-scenes pages made while building the mod (run comparisons, labs, previews). Full reference:
`site/README.md` (read it first). Plan and open work: `plans/site/PLAN.md`.

## Rules (consistency is the point)

- **One design.** The only theme is `site/src/styles/theme.css` (the Organic Towns hub palette, light + dark).
  Never add page CSS, `<style>` blocks or per-mod colors/fonts; build from Tailwind utilities on the theme
  tokens, shadcn components (`src/components/ui/`, Base UI, add more with `pnpm --dir site dlx shadcn@latest add
  <name>`) and the shared pieces in `src/components/site/` and `src/layouts/`. A missing token goes into
  `theme.css` for everyone (colors as one `light-dark()` per token). Font sizes come from the type scale (`text-tag`,
  `text-meta`, `text-hint`, `text-dense`, `text-subhead`, `text-lead`, `text-display`, plus Tailwind's own), never
  `text-[...]`; a new step also goes into `TEXT_SIZES` in `src/lib/utils.ts`. A mod's accent color appears only
  through `bg-mod` / `bg-mod-art`, from the `--mod-accent` that ModLayout (and each home card) sets once.
- **Reuse before inventing.** A new research page first tries a generic kind (`src/components/sections/registry.ts`:
  `image-grid`, `run-compare`, `data-explorer` for result tables, `story` for written pages (article, timeline,
  list), `placeholder`), extended with config options when it almost fits. A mod-specific
  kind (`src/mods/<id>/kinds.ts`) is for genuinely one-off tools (the Name lab). If two mods would want the
  same thing, make it generic. Lists use `components/site/filters/`, labelled controls `components/site/fields.tsx`,
  chips `chipClass` (`src/lib/chip.ts`), run colors `src/lib/run-colors.ts`, card grids `card-grid`, visitor state
  `src/lib/storage.ts` / `usePersistentState` (keys `tf3-site:<modId>/<section>/...`), the theme `src/lib/theme.ts`,
  charts `components/site/charts/BarChart.tsx` and `DeltaChart.tsx` (differences that go either way; story block
  `deltas`, rows from a data file) (load the `dataviz` skill first; colors only from theme tokens),
  before / after `components/site/BeforeAfter.tsx`, image walls `components/site/Mosaic.tsx` and the viewer
  `components/site/Lightbox.tsx`, a mod's changelog `src/lib/changelog.ts`, CSV result tables
  `tools/site_table.py`.
- **Typed sections.** Manifests write generic sections with `runCompare()` / `imageGrid()` / `dataExplorer()` / `story()` / `placeholder()`
  (`src/components/sections/define.ts`); a kind checks its source once in `parseSource` and gets it typed. Loaders fail
  loudly (bad JSON, missing folders, unknown data versions), never show an empty page.
- **URLs use dashes, never underscores:** every href and route goes through `src/lib/slug.ts` (`slugify` /
  `urlPath`) or the builders in `src/lib/mods.ts` (`mod.href`, `sectionHref`, `itemHref`); mod ids and data folders
  keep their names (`square_organic_towns` -> `/square-organic-towns/`, `2026-10-14_a-usa` -> `2026-10-14-a-usa`),
  media paths too (`/media/square-organic-towns/...`). The routes reject underscore slugs. After a build,
  The deploy refuses a build whose pages link an internal URL with `_` (also built file names: astro.config.mjs).
- **Brand color = the posters' teal** (`branding/cover.js` BRAND `#2FA48F`): `bg-brand` / `border-brand` with
  `text-on-brand` for fills, `text-brand-text` for brand-colored text (light `#227768`, dark `#2FA48F`, both AA).
  Never `text-brand`.
- **Every card keeps its image slot:** no image -> `TitleArt` (generated from the title), so cards line up.
- **Metadata is read, not copied:** name/summary from `_metadata/modinfo.json`, cover `_metadata/0.png`,
  tagline/accent `branding/mods.js`, mod.io link `branding/modio_state.json`. A mod without a cover shows generated
  title art: make the cover with the `mod-covers` skill.
- **Builders emit data, never HTML.** Python tools in `plans/<id>/` or `tools/` write JSON (+ images, + a facet
  manifest for image grids) next to their output; the site renders it, and the sentences around it live in the mod's
  `source` (e.g. `describe` / `autoNotes` / `footer` in `compare.ts`). Hand-written notes may use `**bold**` and
  `` `code` `` (`components/site/Inline.tsx`), nothing else; no `set:html` / `dangerouslySetInnerHTML`. Don't add a
  generated `index.html`.
- **Visual first** (user, 2026-10-14): lead with big pictures, comparisons and walls of layouts, not with design notes.
  Landing `highlights` (big images above the copy), then visual sections first (a Showcase story of `mosaic` and
  `pairs` blocks, image grids with the Wall / matrix views, run comparisons), the written material last and short (one
  "Behind the scenes" page of compact lists, timeline, data). Captions short and plain ("Smart Lanes 42.9 km/h, game
  lanes 13.4"). Generate pictures when the game has none (Roundabouts' layout drawings from the mod's own geometry).
- **Lean media:** pick the smallest preset that fits each section (`withPreset("grid" | "view" | "wall", globs)`,
  `MEDIA_RECIPE.presets` in `src/lib/media-core.ts`), crop shots that are mostly empty ground (`crop: { zoom }`), and
  check the dist size after `make site-build`; it should shrink or stay, not grow.
- **Text:** landing copy is short, player-facing, American English; research pages may be technical. Branded
  "square"; never the owner's real name in page content (the domain is fine). Site text is English only.
- **Public:** everything in the build is published, including game data the lab uses (user decision
  2026-10-14). Don't put secrets, tokens or local paths into page data.

## Adding a mod

1. `site/src/mods/<modId>/mod.ts` with `defineMod({ id, landing, sections })`; model it on
   `src/mods/square_organic_towns/mod.ts`. Mod wording for a generic kind lives in the manifest's `source`
   (e.g. `compare.ts`), never in the kind.
2. `landing.mdx`: what it does, in a few short sections; facts from the mod's `description.html` and `PLAN.md`.
3. Image globs in a section's `media` (with a preset: `withPreset(...)`), then `make site-media` (incremental,
   hash-cached).
4. `make site-dev` (port 4321; a second server needs `pnpm --dir site astro dev --ignore-lock --port 4322`), check
   home, landing and each section in light and dark at desktop and 390 px (no page-wide horizontal scroll; wide
   tables scroll inside their box). Phone-width screenshots need CDP device emulation, since headless Chrome on macOS
   won't lay out narrower than ~500 px with `--window-size`.
5. `pnpm --dir site astro check` (0 errors), `pnpm --dir site dlx knip@5` (nothing unused) and `make site-build`.
   shadcn components keep the site edits listed in `site/README.md` ("shadcn components"); redo them after a re-add.

## Porting an existing generated page

Read the old page's JS fully and list its features first; port every one (report anything dropped and why).
Back up untracked originals to the scratchpad before deleting them, switch the builder to data output, update
the plan docs and tool docstrings that describe the old page. Generator logic ported to TS keeps a check against
the source (Name lab: `node plans/square_organic_towns/names/check_port.mjs`).

## Deploy

`make site-deploy` builds and pushes `site/dist/` to the public repo `dylanfisher/tf3-mods-site` (Pages,
`CNAME` tf3.dylanfisher.com). It is outward-facing: **the user runs it**; `DRY_RUN=1` builds and stages without
pushing (it keeps the staged clone and prints the commit stat). The domain is `SITE_URL` in `site/astro.config.mjs`,
its only source. Sources (screenshots, plans data) are local and partly untracked, so there is no CI build.
