Status: in progress, started 2026-10-14. Phases 1-8 done 2026-10-14; open: finish the Name lab move (below), OT cover, first deploy.

# Mod microsites (tf3.dylanfisher.com)

A static site with one microsite per mod: a short player-facing **landing** (what it does, cover, gallery,
mod.io link) and then a **research index**: the behind-the-scenes pages collected while building the mod
(run comparisons, labs, previews, result tables). Organic Towns is the first and model mod; the current
hand-written hub (`plans/square_organic_towns/index.html` + `compare/`, `names/`, `svg/`) is ported fully.

## Decisions (user, 2026-10-14)

- Public site, mostly research hub; landing = quick player showcase. Branded **square**; URL under the
  owner's handle is fine: custom domain `tf3.dylanfisher.com`.
- Stack: latest Astro (static output) + React islands, latest Tailwind (v4, CSS-first `@theme`), shadcn/ui
  on **Base UI** primitives (not Radix). pnpm. Lives in `site/`.
- Design must be consistent and DRY across every mod: one theme (tokens from the current Organic Towns hub:
  warm off-white / near-black, teal accent, quiet bordered cards, system font, light + dark), one layout,
  shared section components. A mod adds data + a manifest, not CSS.
- Full port of the interactive pages to components. The Python builders emit **data** (JSON + images),
  never HTML; the site renders it.
- Publish every generated image, through a media build step: resize + WebP at sensible sizes, cached by
  content hash so reruns are incremental.
- Deploy: a separate public repo (`dylanfisher/tf3-mods-site`, Pages from its branch, `CNAME`
  tf3.dylanfisher.com). Sources (plans/**, screenshots) are local/untracked, so the build runs **locally**
  and a script pushes `site/dist/` to that repo. The user creates the repo and runs the push (outward-facing).
- Name lab stays fully interactive (visitor edits in localStorage, export downloads a file).

## Architecture (target)

```
site/
  astro.config.mjs, package.json, components.json (shadcn, base-ui), tsconfig.json
  src/styles/theme.css            the only theme: Tailwind @theme + shadcn tokens, light/dark
  src/components/ui/              shadcn components (generated, Base UI)
  src/components/site/            shared building blocks: SiteHeader, ModHero, SectionCard, StatRow,
                                  Gallery, fields, filters, Inline, TitleArt, Footer, ThemeToggle ...
  src/components/sections/        generic section kinds reused by any mod (e.g. run-compare browser +
                                  viewer, image grid, gallery)
  src/layouts/                    BaseLayout, ModLayout (hero + breadcrumb + section nav)
  src/mods/<modId>/               per mod: manifest (mod.ts: id, sections, sources) + landing copy (MDX)
                                  + mod-specific components only when no generic kind fits (e.g. name lab)
  src/pages/index.astro           all mods with a microsite (cover, name, tagline from modinfo/branding)
  src/pages/[mod]/...             generic routes driven by the manifests
  scripts/media.mjs               sharp: source images -> public/media/<mod>/... WebP (thumb + full per preset,
                                  optional crop), hash cache
  scripts/deploy.sh               build + push dist/ to the public repo
```

Mod metadata is read, not duplicated: name/summary from `mods/<id>/_metadata/modinfo.json`, cover
`_metadata/0.png`, tagline/accent from `branding/mods.js`, mod.io id from `branding/modio_state.json`.
Generated media and copied data live under gitignored paths (`site/public/media/`, `site/.cache/`).

Make targets: `site-dev`, `site-media`, `site-build`, `site-deploy` (user runs deploy).

## Phases

1. **System scaffold** (done 2026-10-14): `site/` with Astro + React + Tailwind v4 + shadcn (Base UI), theme from the OT hub
   tokens, layouts, shared components, manifest loader + generic routes, home page, media pipeline,
   deploy script, make targets. An Organic Towns landing stub proves the flow.
   Built: Astro 7.3.8 + @astrojs/react 7.0.1 + @astrojs/mdx 8.0.3, React 19.3.0, Tailwind 4.3.3, shadcn 4.21.5
   (`base-nova` style on `@base-ui/react` 1.9.0), sharp 0.35.5, pnpm. Manifests `src/mods/<id>/mod.ts`
   (`defineMod`, `src/lib/define-mod.ts`); section kinds in `src/components/sections/registry.ts` (generic:
   `placeholder`, `image-grid`) plus per-mod `src/mods/<id>/kinds.ts` (`"<modId>/<name>"`); reusable list
   toolkit `src/components/site/filters/` (and a `DataTable.tsx`, removed unused in phase 5). Media: 482 OT sources (327 JPEG + 155 SVG,
   122 MB) -> 118 MB in 10 s with 8 jobs, rerun 0.1 s (all cached); SVGs are copied plus a raster thumb.
   OT stub: landing MDX, gallery of 8 tour shots, three `placeholder` sections showing their images.
   How-to: `site/README.md`.
2. **Organic Towns port** (done 2026-10-14): comparison browser + viewer as the generic `run-compare` kind with
   sub-pages (`[mod]/[section]/[item]`), OT wording in `src/mods/square_organic_towns/compare.ts`; street plans on
   the generic `image-grid` kind with facets, matrix and lightbox (`svg/previews.json`, 155 SVGs); Name lab as the
   mod kind `square_organic_towns/name-lab` (TS port matches Lua 3792/3792, `names/check_port.mjs`).
   `build_compare.py`, `export_names.py`, `tools/ot_preview.py` write data only; `build_index.py`, the hub
   `index.html`, `compare/template.html`, `compare/*/index.html` and `svg/index.html` deleted (backups were in the
   session scratchpad).
3. **Skill + docs** (done 2026-10-14): `.claude/skills/mod-sites/SKILL.md`, CLAUDE.md commands line.
4. **System polish** (done 2026-10-14): dashed URLs everywhere (`src/lib/slug.ts`; mod, section, item and media
   paths, `/assets/` instead of `/_astro/`; routes reject `_`); every card keeps its image slot, with generated
   `TitleArt` (title fitted to the slot over brand + accent color fields) as the fallback, also for mod covers, and an
   optional section `thumb`; run-compare pages viewer first (`source.order`, default `"viewer-first"`); brand teal =
   the posters' `#2FA48F` fill with `#0f1d1b` text on it, `--brand-text` `#227768` (light) / `#2FA48F` (dark) for
   brand-colored text (AA on bg, panel and chip).

5. **Review fixes** (done 2026-10-14, from a code review of phases 1-4): type scale (`--text-*`, registered with cn
   in `src/lib/utils.ts`); palette as `light-dark()`; shared `src/lib/storage.ts` + `usePersistentState`, `run-colors.ts`,
   `theme.ts` (setTheme; the Name lab's `#theme=`), `fields.tsx` (LabeledSelect / LabeledCheckbox), `Inline.tsx`
   (inline markup), `card-grid` utility, `chipClass` everywhere; typed sections (`parseSource`, `define.ts` helpers,
   `resolve.ts`, typed kind components); loud loaders; run-compare made generic (`units` / `extraUnits`, `#unit=`,
   neutral default unit, dates from `built`, data version 3 without HTML: `describe` / `autoNotes` / `footer` in
   `compare.ts`; version 2 still read) and CompareViewer split into `viewer/`; ImageBrowser on the list toolkit (group
   choices); media recipe hashed into the cache, failed sources keep their output; deploy: one CNAME source
   (`SITE_URL`), underscore gate, kept dry-run clone, visible clone errors; dashed chunk names; dead code removed
   (DataTable, Chip(s), unused shadcn files); knip config.

6. **Roundabouts & Interchanges microsite** (done 2026-10-14): landing (modinfo, 9 mod.io slides) and eight research
   sections built from the plan docs, the probe CSVs, the test timings and 73 screenshots (39 curated captures in
   `plans/square_roundabouts/shots/`, 34 test-session screenshots copied to `plans/square_roundabouts/site/shots/`, 3
   settings-panel crops). New generic pieces: kind `data-explorer` (result tables with filters, breakdown chart, sortable
   table; data from `tools/site_table.py`, published through the new `KindDef.files` route `/data/<mod>/<section>/<file>`),
   kind `story` (typed blocks as article / timeline / list; timeline reads the changelog, `src/lib/changelog.ts`),
   `components/site/charts/BarChart.tsx` (theme tokens `--chart-pass` / `--chart-fail`, palette validated),
   `components/site/BeforeAfter.tsx` (ShotSlider now uses it), image-grid manifests may use `../` paths. Builder:
   `uv run plans/square_roundabouts/site/build_data.py` (probe tables, test timings, gallery manifest, panel crops).

7. **Smart Lanes microsite** (done 2026-10-14): landing (modinfo, 9 mod.io slides) and ten research sections: how it
   works, timeline (with the changelog), design decisions, problems solved, tested against the game, a case study (the
   faster roundabout), the nine Stress Test bench runs as run-compare pages (twins side by side / slider with the bench's
   own screenshots), measurement tables (bench and showcase pairs, twins, junction audit, SQPERF slow calls, test
   timings), testing and performance, screenshots (16 curated, 25 picked test-session captures, 51 bench shots). New
   generic pieces: `components/site/charts/DeltaChart.tsx` and the story block `deltas` (rows written out or read at
   build time from a data-explorer file: numbers stay in the builder's output), run-compare `runName` (e.g. "twin") and
   `notes` in the facts given to `describe` / `autoNotes`, one unit name in the viewer heading when all runs agree.
   Builder: `uv run plans/square_smart_lanes/site/build_data.py` (reads `.cache/logs/` through tools/bench_report.py and
   tools/flow_report.py; `--no-shots` keeps the copied images).

8. **Visual-first rework of Roundabouts and Smart Lanes** (done 2026-10-14, user feedback: the pictures and comparisons
   are the interesting part, not the design notes). Generic: media presets (`default` / `view` / `grid` / `wall`) and
   center crops per media spec (`withPreset`, `MediaSpec`; largest preset wins per source), `components/site/Mosaic.tsx`
   (justified image wall) and `Lightbox.tsx` (shared viewer), image-grid Wall view, `source.view`, one matrix per group,
   `srcset` on grid thumbs; story blocks `mosaic` and `pairs`; landing `highlights`. Roundabouts: Showcase, Every layout
   (176 plan drawings from the mod's own geometry, `plans/square_roundabouts/site/layouts.py`), Screenshots, Behind the
   scenes (how it works, decisions, problems, negative zero, testing merged and shortened), Timeline, Probe data. Smart
   Lanes: Showcase (14 twin sliders from `showcase.json`), Every twin (`twins.json` wall), Results in charts, Bench runs,
   Screenshots, Behind the scenes, Timeline, Measurements. Organic Towns' comparisons on the `view` preset, its street
   plans' thumbs on `grid`. Media 167 MB -> 118 MB (dist 181 -> 128 MB) with 192 more sources.

## Open

- The bench shoots only the first set of each test (`BENCH_SHOT`, 51 shots in all), and the archived logs hold no other
  automated screenshots of these two mods (the rest of the game's screenshot folder is Organic Towns, Photo Mode and
  SQPQ). More twins on the site need a Stress Test change: a shot of every set (`plans/square_stress_test/`).
- The Name lab's data file (`plans/square_organic_towns/names/data.json`, published as `/assets/data.*.json`) carries a
  local log path in `map.log`; the Name lab's exporter should drop it (another session's area).
- Street-plan SVGs (Organic Towns, 155 files, 44 MB) are published as they are; a minify step would cut most of it
  (Pages gzips them in transit).

- `export_names.py` writes `names/data.js` (window.NAMEDATA) again beside `data.json`, for the old page and
  `check_port.js`; drop that when the old page goes.
- The existing comparison pages are still data version 2 (read through the fallback); a `build_compare.py --rebuild`
  turns one into version 3 but also re-reads the logs with today's parser (Z2tNDhy0Ht's run-row counts would change),
  so rebuild them when that is wanted.
- **Name lab move not finished:** another session kept extending the old `names/` lab (lab.js "Whole map (plan)"
  mode, map SVG, shape quotas, A/B test, log import; gen.js changes) during the port. Port those into the island,
  then delete `names/index.html`, `lab.js`, `gen.js`, `ideas.js`, `port_check.js`, `check_port.js`, `data.js` and
  make `gen.ts` the only port. Since 2026-10-15 (Organic Towns NEXT_PHASE_BRIEF 60) gen.ts is the source and
  `plans/square_organic_towns/names/gen_js.mjs` generates gen.js from it; lab.js changes still need porting.
- OT has no `_metadata/0.png` / `branding/mods.js` entry (generated title art on the site): `mod-covers` skill.
- First deploy: user creates `dylanfisher/tf3-mods-site`, DNS CNAME `tf3` -> `dylanfisher.github.io`,
  `make site-deploy`, Pages settings (`site/README.md` "Hosting").
- Run colors are 4 (`src/lib/run-colors.ts`); Smart Lanes' bench pages have 5 twins (8 on micro bench v2), so colors
  repeat there (every run is labelled, so identity never rests on color). Two more hues (#1f6fb2 / #5e6b1f light) failed
  the dataviz validator over all pairs (they collide with the brown run-1), as does the current dark set's lightness band:
  a validated 6-8 color run palette is open.
- React 19.3.1 was held back by pnpm's minimum release age; bump later.
- Name lab data contains the game's own town-name lists (gitignored in this repo for that reason): the user
  chose to publish it as-is on the site (2026-10-14). It stays gitignored here; only the deploy repo gets it.
