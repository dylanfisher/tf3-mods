# Square house style: mod covers

Every mod ships under the creator name **square** (modId `square_<name>`, modinfo author `square`) and gets a cover in one shared look: the **Diagonal Split**.

```
┌──────────────────────────────┬─────────────┐
│ ░ family teal ░░░░░░░░░░░░ ╱ ╱  dark        │
│ Title In Overpass 800    ╱ ╱                │
│ Tagline in Overpass 600 ╱ ╱    [pictogram]  │
│                       ╱ ╱       in mod      │
│                     ╱ ╱         accent      │
└───────────────────╱─╱───────────────────────┘
```

## Files

| File | What |
|---|---|
| `cover.js` | The renderer: palette, layout, pictogram helpers (`factory`, `ground`, `arrowHead`). Change the look here, and it changes for every mod. |
| `mods.js` | One `Square.register({...})` per mod: id, name, tagline, accent, pictogram. |
| `index.html` | Gallery: every cover in a mod-browser mock. Open it in a browser (`open branding/index.html`). |
| `render.html` | A single cover at exactly 1920×1080, which `make covers` screenshots. |
| `fonts/` | Overpass 600/800 and Overpass Mono 700 (OFL), so renders work offline. |
| `flags/` | Sanitized state flags for the State series (`<stateKey>.svg`) and `SOURCES.json`, which pins each one (Commons page, URL, sha1, licence, author, aspect). Written by `make flags`; never edit by hand. |

## Adding a cover for a new mod

1. Add a `Square.register({...})` entry to `mods.js`:
   - `id`: the modId, which is also the folder name.
   - `name`: exactly the `name` in `_metadata/modinfo.json`.
   - `tagline`: about 32 characters at most, in English, sentence case, no full stop. It says what the player gets, not how the mod works.
   - `accent`: a colour that's distinct from the other mods (see the palette below).
   - `glyph(S)`: the pictogram, drawn in an 800×800 box.
2. Open `index.html` and check the cover in the mod-browser grid at thumbnail size.
3. Run `make covers MOD=mods/<id>`. It writes `mods/<id>/_metadata/0.png` (1920×1080, the wiki's cover spec).

## Fixed elements (don't vary per mod)

- **Canvas**: 1920×1080. The diagonal runs at 45°, from (1540, 0) to (460, 1080), with a 16 px teal stripe 70 px to its right.
- **Family teal** `#2FA48F` with a soft white-to-black sheen on the title side. The pictogram side is dark `#18202a`.
- **Title**: top-left (first baseline at y=200, x=108), Overpass 800, 130 px, colour `#0f1d1b`. **Tagline**: Overpass 600, 74 px, 75 % opacity, 120 px below the last title line. Both wrap to the room left of the diagonal at each line (estimated per character in `cover.js`), so short names stay on one line; a tagline that doesn't fit splits into two with the longer half on top (first space past the middle). A `\n` in the tagline forces the break there instead (Better Minimap).
- **No creator logo**: covers and slides carry no "square" mark. The shared teal, diagonal and type are the family signal.
- **Pictogram**: 640 px, on the dark side.

## Pictograms

- Flat, rounded and geometric, like the game's own UI icons: filled shapes, generous corner radii, no outlines-only drawings, no gradients, no text.
- Use the CSS classes, never hard-coded theme colours, so a future restyle carries through:
  - `ink`: main shapes (near-white).
  - `acc`: the mod's accent. Use it for the one or two elements that carry the idea, such as the flow arrows or the "no" sign.
  - `cut` / `cutf`: knock-outs in the background colour, such as windows or symbols inside an accent shape.
  - `sink` / `sacc` / `scut`: the same three colours as strokes.
  - `sep`: a 10 px background-coloured outline that separates overlapping shapes.
  - `under`: an opaque background-coloured fill behind a translucent shape.
- Reuse the helpers for shared motifs: `S.factory(x, y, scale)` for any industry, `S.ground(x, w, y)` for a base line, `S.arrowHead(x, y)`, and `S.LINE_COLORS` for line-colour dots.
- Keep the pictogram readable at thumbnail size (about 160 px tall in the grid): three or four shapes, nothing thinner than about 12 px.

## Accent palette in use

| Mod | Accent |
|---|---|
| Quota Run | `#F2B33D` amber |
| Bigger Line Dots | `#4FA3E0` blue |
| Industry Flows | `#33C2B0` teal |
| Industry Production Label | `#8BD450` green |
| No Factory Passengers | `#E5554F` red |
| Problem Radar | `#F1B43D` amber |
| Better Minimap | `#E8B740` gold (matches the in-game camera box). Instead of a pictogram it shows a large rounded card of the real game (the first slide's crop of `plans/square_better_minimap/shots/01-overview.jpg`) laid across the diagonal. |
| Roundabouts & Interchanges | `#E8833A` orange |
| Early One-way Roads | `#9B7BE0` purple |
| Bulk Bulldozer | `#F4D32B` hazard yellow (lighter and greener than the ambers) |
| Line Editor Undo | `#C964E8` orchid (bluer and brighter than the pink, redder than the purple) |
| Smart Lanes | `#3FD6EE` sky cyan (lighter and greener than the blue, bluer than the teal) |
| Better Bus Overlay | `#5B7CFA` royal blue (deeper and more violet than the Bigger Line Dots blue, bluer than the purple) |
| Supply Gap Overview | `#C2E83A` lime (yellower than the Industry Production Label green, greener than the hazard yellow) |
| Blank Slate: Empty Flat Test Map | `#7CF0B4` mint (the sea around the island) |
| Passenger Destinations | `#FF8A65` coral (lighter and pinker than the roundabout orange, more orange than the No Factory Passengers red) |
| Stress Test Debug Tool | `#F048D8` hot magenta (more saturated than the Full Refund pink, redder than the Line Editor Undo orchid) |
| State series (`<State> Towns & Streets`) | The flag's main colour (Washington `#00843D`), or a secondary one when the main is generic (Arizona `#CE5C17`, the copper star; Florida `#C60013`, the red saltire; Colorado `#00205B`, the blue bands; California `#5C462B`, the bear brown, since its red and green are taken; Texas `#BF0A30`, the flag red, since its blue is exactly Colorado's; Alaska `#FFB612`, the gold stars, since its dark blue is close to Colorado's; New York `#ECC875`, the seal's gold, since its blue field is close to Colorado's and its red to Texas's; Minnesota `#52C9E8`, the 2024 flag's light blue, since its dark blue is close to Colorado's; New Mexico `#0095B6`, turquoise (the state gem), since the Zia red is Texas's and its yellow sits next to Alaska's gold and the hazard yellow; Oregon `#2C5E3F`, Douglas fir green (the state tree), since the navy is close to Colorado's and the gold to Alaska's and New York's; Pennsylvania `#1F5290`, the seal shield's sea blue, since its blue field is exactly Colorado's and the seal's gold, red and green sit next to Alaska's/New York's, Texas's and Washington's; Hawaii `#D63384`, hibiscus pink (not a flag colour), since the flag's navy is close to Colorado's and its red to Florida's and Texas's). Recorded only; the series pictogram is all ink and the flag sticker carries the colour, so state accents may repeat or sit close to other mods. |

Pick the next mod's accent away from these, for example sand `#D9B98C`. Avoid the family teal `#2FA48F`, the fork orange `#E2873B` and the DEV grey `#8E9BAE`.

## Local forks (SQ Opt)

Local "SQ Opt" forks of other authors' mods (`square_opt_<upstreamId>`, never uploaded) use the same Diagonal Split with **fork orange** `#E2873B` in place of the family teal, on both the title field and the stripe, so a local override stands out in the in-game mod list. The pictogram is a generic ink branch splitting off a main line, with an orange lightning bolt (optimized); the tagline is "Local copy, not for upload". It all lives in `cover.js` (`FORK`, `forkCover`), so change it there for every fork at once.

`make fork-new` adds the `Square.forkCover({ id, name })` line to `mods.js` itself; then run `make covers MOD=mods/<forkId>`. `tools/fork_mod.py` treats `_metadata/0.png` as the fork's own file, so an upstream merge never brings the author's cover back. Don't use fork orange for anything else.

## DEV mods (test harnesses and probes)

Our own DEV mods (a `DEV …` display name and a `NOT_FOR_UPLOAD.txt`, never uploaded: perf harnesses, API probes) use the same Diagonal Split with **DEV grey** `#8E9BAE` in place of the family teal, on both the title field and the stripe. Grey is the one hue no accent, state colour or fork uses, and it reads as "not a real mod" in the in-game mod list; the title ink `#0f1d1b` keeps about 6.2:1 contrast on it (the teal gives 5.6:1). The pictogram is one shared lab flask: an ink flask with a knocked-out neck, grey liquid with two knocked-out bubbles. The default tagline is "Dev tool, not for upload"; a mod may pass a short specific one instead. It all lives in `cover.js` (`DEV`, `devGlyph`, `devCover`), so change it there for every DEV mod at once.

**Groups.** DEV mods of one kind share a colour, set with `group` (`DEV_GROUPS` in `cover.js`). The title field is a diagonal gradient from the group's unsaturated `from` colour (top left, behind the text) to its saturated `to` colour (bottom right, at the diagonal); the stripe and the flask liquid use `to`. Groups: `perf` blue `#8FA9C2` → `#3F9BF0` (perf harnesses, SQPERF), `roundabouts` yellow `#BFAE7E` → `#E8C21E` (Roundabouts & Interchanges probes, kept away from the fork orange), `lines` violet `#AE9DC2` → `#B66EF2` (line tools probes), `names` green `#95AE8B` → `#6CCB45` (town and street names probes). The shared layout and flask keep them one DEV family, and the title ink keeps at least 5.6:1 contrast across the whole gradient. An ungrouped DEV mod keeps the flat grey. For a probe of a new mod family, add a group to `DEV_GROUPS` (a greyish `from`, a saturated `to` of the same hue, title-ink contrast at least 4.5:1 on both, away from the teal, the fork orange and the existing groups) instead of reusing one.

Add one `Square.devCover({ id, name, group })` line to `mods.js` (optional `tagline`, and `titleLines` when the automatic wrap breaks badly, as for `DEV SQPERF: all mods`), then `make covers MOD=mods/<id>`. The title keeps the `DEV ` prefix so it matches modinfo. Not for shipped mods, even debug tools that are uploaded (Stress Test Debug Tool has its own cover), and not for SQ Opt forks. Don't use DEV grey for anything else.

## State series (`<State> Towns & Streets`)

The US State Names mods (`square_names_us_<state>`, plan in `plans/square_state_names/`) share one cover: the normal Diagonal Split plus the state flag stuck on like a sticker. Every state looks the same except for the first title line and the flag, so the series reads as a set in the mod browser. All of it lives in `cover.js` (`STICKER`, `streetSign`, `stateCover`). Change it there, for every state at once, and never per state.

- **Title**: two fixed lines, `<State>` / `Towns & Streets` (not the automatic wrap). **Tagline**: `Real towns, streets & stations`, which wraps after "streets".
- **Pictogram**: an ink street-name sign: a blank blade with two knocked-out text bars, top right of the dark side, and its post running down behind the sticker to a base. All ink, no accent.
- **Sticker**: the flag, **1000 px** wide (height from the flag's aspect), centred at (1440, 690), tilted **-7°**: it overtakes the right half of the card and runs off the right and bottom edges (on purpose: it looks slapped on). A 22 px white die-cut border with a 26 px corner radius, and a drop shadow (dy 16, blur 22, 45 % black). The bottom-right corner is peeled back along a 120 px diagonal: the cut-off corner shows the dark background, and a grey-to-white fold with a slight curl and a small shadow lies on the flag. A faint diagonal gloss sits over the flag. The sticker sits in front of the pictogram and clears the title.
- **Flag**: drawn as-is, stretched to the box (no cropping), from `flags/<stateKey>.svg`. A flag much taller or wider than 1.5–1.9 changes the sticker's height only, never its width, position or tilt.

### Adding a state's cover

1. Pin the flag: `make flags ARGS='--lookup "Flag of Oregon.svg" --key us_oregon'` prints a `SOURCES.json` entry (licence, author, sha1, aspect). Check the licence, then add the entry to `flags/SOURCES.json`. The tool refuses anything but Public domain / CC0 without `--allow`.
2. `make flags STATE=us_oregon` downloads the pinned file into its own empty folder `.cache/flags/raw/us_oregon/`, verifies the sha1, and sanitizes it with an isolated interpreter (`python -I tools/sanitize_svg.py`, allow-list of shapes and gradients, no scripts, event handlers, external links or images) into `flags/us_oregon.svg`. Check the printed element counts: a flag that loses visible elements needs a look.
3. Add one line to `mods.js`, with `id` at the start of a line (`render_covers.py` finds mods that way):
   `Square.stateCover({ id: 'square_names_us_oregon', state: 'Oregon', flag: 'us_oregon.svg', flagAspect: 1.6667, accent: '#002A86' });`
   `flagAspect` is the `aspect` from `SOURCES.json`; `accent` is the flag's main colour (for the palette table only).
4. Check it in `index.html`, then `make covers MOD=mods/square_names_us_oregon`. A state name longer than about 14 characters ("North Carolina", "South Dakota") still fits on the first line; check it anyway.

## Gallery slides (`_metadata/1.png`, `2.png`, …)

Same family as the cover: the teal panel on the left carries the mod name, a 2–4 word headline and one short line; the right side shows a crop of a real game capture on the dark field. `slide.js` draws them, `shots.js` holds the per-mod list, and `make shots MOD=mods/<id>` renders them (stale higher-numbered slides are removed; `0.png` is never touched).

- **Captures**: full-screen, Retina 5120×2880, saved to `plans/<id>/shots/NN-slug.jpg` (never shipped). English UI, same UI scale, no other mods in frame.
- **Crop to the point**: `crop: [x, y, w, h]` in capture pixels. Show the window, label or area the slide is about, never the whole screen. The quickest way to find coordinates is a 1280-wide preview (multiply by 4).
- **Layouts**: `single` (one crop), `inset` (scene plus a UI crop overlapping a corner, e.g. the panel that produced it, or a zoom of a small HUD element; `insetW` sets its width, and optional `insetY` centres it at that fraction of the slide height instead of the corner), `wipe` (two same-camera captures split on a 45° diagonal, labelled Off/On), `stack` (the same UI in two states, labelled).
- Keep headlines to what the player gets, like the cover tagline. 3 slides per mod is plenty.
- **After the first upload, sync the gallery with `make modio`.** A Mod Hub update does not replace gallery images that mod.io already has under the same number: it only adds new numbers (Problem Radar rev 2: the new economy slide rendered as `3.png` and pushed the settings slide to `4.png`, but mod.io kept the old `3.png` and showed settings twice). `make modio MOD=mods/<id>` shows whether mod.io's gallery and logo match `_metadata/`, and `ARGS=--apply` replaces the whole gallery with the local `1.png`, `2.png`, …, uploaded as `N-<hash>.png` so a changed slide gets a new URL (re-using `1.png` kept showing the old picture from caches). The Hub re-sends the slides on every update, so run it after each Hub update (CLAUDE.md "Releasing updates").

## Mod description (`_metadata/description.html`)

Every mod ships its description as `_metadata/description.html`. When that file exists the game uses it instead of modinfo's `description`, both in the in-game browser and on mod.io (`docs/wiki/modding/general/moddefinition.md:28,176`). The Mod Hub changelog field takes only one line, so **the changelog lives in the description**. Every mod has one, and every update that bumps `revision` adds an entry.

- **Every piece of text sits in a block**: prose in `<p>`, headings in `<h2>`/`<h4>` (see Headings), list entries in `<li>`. No loose text between tags, and no `<br>` to fake paragraphs.
- **Formatting**: only what the in-game browser renders: `<p>`, `<h1>`–`<h4>`, `<strong>`, `<ul>`/`<ol>`/`<li>`, `<hr>` (`docs/wiki/modding/general/guidelines.md:189-196`; the wiki lists only Header 1–3, so check that `<h4>` renders in game). No tables, images or video; those go in the gallery slides. mod.io caps the description at 150,000 characters (`api.mod.io/v1/swagger`, mod `description.maxLength`).
- **Headings**: `<h2>` is used once, for the Changelog title. Every other heading is an `<h4>`: the section titles (Features, Settings, Notes) and each revision entry in the Changelog. No `<h1>` or `<h3>`.
- **Structure**, in this order:
  1. One or two `<p>` paragraphs on what the player gets (same voice as the cover tagline).
  2. `<h4>Features</h4>` with a `<ul>` of what it shows or does.
  3. `<h4>Settings</h4>` when `mod.json` has `params`: each option by its exact in-game name, and its default.
  4. `<h4>Notes</h4>` for caveats and save compatibility ("reads the game state only, safe to add to or remove from existing saves" where true).
  5. `<hr>` then `<h2>Changelog</h2>`. Each revision gets an `<h4>` (`Revision N`, plus the upload date as `YYYY-MM-DD`) and a `<ul>` of changes, **newest first**. Start each item with New, Changed or Fixed.
- The description is English only: mod.io holds one description per mod. Translated name and summary go in modinfo's `localization` block (CLAUDE.md "Translations"). Name settings by their English in-game text.
- Keep modinfo's `description` as a short plain-text fallback (the summary plus one sentence). The `summary` stays ≤100 characters on a single line.
- `make validate` warns when `description.html` is missing, has no Changelog heading, has no entry for the current `revision`, has text outside `<p>`/heading/`<li>` blocks, uses `<h2>` for anything but the Changelog, uses `<h1>`/`<h3>`, or uses tags the game doesn't render.

Template:

```html
<p>What the player gets, in one or two sentences.</p>
<h4>Features</h4>
<ul>
<li><strong>Thing one</strong>: what it shows.</li>
</ul>
<h4>Settings</h4>
<ul>
<li><strong>Option name</strong> (default On): what it does.</li>
</ul>
<h4>Notes</h4>
<ul>
<li>Reads the game state only and stores nothing in the savegame.</li>
</ul>
<hr>
<h2>Changelog</h2>
<h4>Revision 1 (YYYY-MM-DD)</h4>
<ul>
<li>First release.</li>
</ul>
```
