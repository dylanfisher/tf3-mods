---
name: mod-covers
description: Square house-style mod covers (_metadata/0.png) and gallery slides: branding/mods.js entries, pictograms, make covers, make shots. Use when creating a new mod's cover, renaming a mod, changing the cover look, or adding gallery screenshots.
---

# Mod covers (square house style)

Every mod gets a `_metadata/0.png` cover in the shared **Diagonal Split** look: family teal on the left with title and tagline, a dark field on the right with a flat pictogram in the mod's accent colour, and no creator logo. The full rules are in `branding/README.md`. Read it before drawing a pictogram.

- New mod: add a `Square.register({...})` entry to `branding/mods.js` (id, name matching modinfo, tagline of up to 4 lines (about 32 characters wraps by itself; longer needs `\n` breaks, see `branding/README.md`), an accent distinct from the existing ones, and a pictogram built from the shared CSS classes and helpers). Preview it in `branding/index.html`, then run `make covers MOD=mods/<id>`.
- Changing the look (palette, layout) happens only in `branding/cover.js`, followed by `make covers` for all mods. Don't hand-edit a single `0.png` or fork the style per mod.
- After a mod is renamed, update its `name` in `mods.js` and re-render.
- Gallery slides: drop full-screen captures into `plans/<id>/shots/` (named `NN-slug.jpg`), add a `Square.slides(...)` entry to `branding/shots.js` with crops of just the relevant part, then `make shots MOD=mods/<id>`. See `branding/README.md`.
