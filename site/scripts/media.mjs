#!/usr/bin/env node
// Media build: every image a mod manifest declares (src/mods/*/mod.ts: cover, gallery, section media) ->
// site/public/media/<mod-slug>/<path>.webp (full) + <path>.thumb.webp, never upscaled, at the sizes and quality of the
// preset the declaring section asks for (MEDIA_RECIPE.presets in src/lib/media-core.ts: default 1600 / 480 px, view,
// grid, wall; a source declared by several sections gets the largest), after an optional center crop. SVGs are copied
// as they are, plus a raster .thumb.webp. Cached by source content hash and recipe hash in site/.cache/media.json, so a rerun only
// processes new or changed files (and everything after a recipe change); outputs whose source is gone are removed.
// A source that fails keeps its previous outputs and cache entry (and the run exits 1).
//
//   node scripts/media.mjs [--force] [--mod <modId>] [--jobs N]
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import sharp from "sharp";
import {
  cropBox, entryKey, isSvg, largerPreset, MEDIA_CACHE, MEDIA_DIR, MEDIA_RECIPE, mediaStem, mediaUrl, RASTER_RE, recipeHash,
  variantKey,
} from "../src/lib/media-core.ts";
import { manifestMedia } from "../src/lib/define-mod.ts";

const SITE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const REPO = path.resolve(process.env.TF3_REPO_ROOT ?? path.join(SITE, ".."));
const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const FORCE = flag("--force");
const ONLY = opt("--mod");
const JOBS = Math.max(1, Number(opt("--jobs")) || Math.min(8, os.availableParallelism()));
const R = MEDIA_RECIPE;
const RECIPE = recipeHash();

sharp.concurrency(Math.max(1, Math.floor(os.availableParallelism() / JOBS)));

const cachePath = path.join(SITE, MEDIA_CACHE);
let cache = { recipe: RECIPE, entries: {} };
let staleRecipe = false;
try {
  const c = JSON.parse(fs.readFileSync(cachePath, "utf8"));
  // Another recipe: keep the entries (their files are swept below when replaced), but process every source again.
  cache = { recipe: RECIPE, entries: c.entries ?? {} };
  staleRecipe = c.recipe !== RECIPE;
} catch { /* first run */ }

// ---- collect sources from the manifests ----
const manifestFiles = fs.globSync("src/mods/*/mod.ts", { cwd: SITE }).sort();
const jobs = new Map(); // key -> { mod, src, spec: { preset, crop? } }
const sameCrop = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
for (const f of manifestFiles) {
  const m = (await import(pathToFileURL(path.join(SITE, f)).href)).default;
  if (ONLY && m.id !== ONLY) continue;
  for (const g of manifestMedia(m)) {
    const d = typeof g === "string" ? { glob: g } : g;
    const preset = d.preset ?? "default";
    if (!MEDIA_RECIPE.presets[preset]) throw new Error(`media: ${m.id}: unknown preset '${preset}' for ${d.glob}`);
    const hits = fs.globSync(d.glob, { cwd: REPO }).filter((p) => RASTER_RE.test(p) || isSvg(p)).sort();
    for (const hit of hits) {
      const src = hit.split(path.sep).join("/");
      const key = entryKey(m.id, src);
      const prev = jobs.get(key);
      // A crop belongs to the source: a declaration without one takes the other's; two different crops are an error.
      if (prev?.spec.crop && d.crop && !sameCrop(prev.spec.crop, d.crop)) throw new Error(`media: ${src} is declared with two different crops (${m.id})`);
      const crop = d.crop ?? prev?.spec.crop;
      const spec = { preset: prev ? largerPreset(prev.spec.preset, preset) : preset, ...(crop ? { crop } : {}) };
      jobs.set(key, { mod: m.id, src, spec });
    }
  }
}

// Two sources must not map to one output (mods/<id>/x.png and plans/<id>/x.jpg).
const stems = new Map();
for (const { mod, src } of jobs.values()) {
  const s = mediaStem(mod, src);
  if (stems.has(s)) throw new Error(`media: ${src} and ${stems.get(s)} both map to media/${s}`);
  stems.set(s, src);
}

// ---- process ----
const stats = { processed: 0, cached: 0, failed: 0, bytesIn: 0, bytesOut: 0, newIn: 0, newOut: 0 };
const outAbs = (url) => path.join(SITE, "public", url);
const variantOk = (v) => v && fs.existsSync(outAbs(v.url));

async function processOne(key, { mod, src, spec }) {
  const P = R.presets[spec.preset];
  const vkey = variantKey(spec);
  const abs = path.join(REPO, src);
  const buf = await fs.promises.readFile(abs);
  const hash = crypto.createHash("sha1").update(buf).digest("hex");
  const prev = cache.entries[key];
  const stem = mediaStem(mod, src);
  // An output path rule change (e.g. slugified URLs) also reprocesses: the old files are removed below.
  const sameStem = prev && prev.full.url.startsWith(mediaUrl(stem, "."));
  if (!FORCE && !staleRecipe && prev && prev.hash === hash && prev.variant === vkey && sameStem && variantOk(prev.full) && variantOk(prev.thumb)) {
    stats.cached++;
    return prev;
  }
  const dir = path.dirname(outAbs(mediaUrl(stem, "")));
  await fs.promises.mkdir(dir, { recursive: true });
  let entry;
  if (isSvg(src)) {
    const url = mediaUrl(stem, ".svg");
    await fs.promises.writeFile(outAbs(url), buf);
    let width = 0, height = 0;
    try { ({ width = 0, height = 0 } = await sharp(buf).metadata()); } catch { /* keep 0 */ }
    const full = { url, width, height, bytes: buf.length };
    // A raster thumb keeps grids of large SVGs (street plans: thousands of shapes each) light to show.
    let thumb = full;
    try {
      const turl = mediaUrl(stem, `.thumb.${R.format}`);
      const info = await sharp(buf, { density: R.svgDensity }).resize({ width: P.thumbWidth, withoutEnlargement: true })
        .webp({ quality: P.thumbQuality, effort: R.effort }).toFile(outAbs(turl));
      thumb = { url: turl, width: info.width, height: info.height, bytes: info.size };
    } catch { /* not rasterizable: the SVG serves as its own thumb */ }
    entry = { mod, src, hash, bytesIn: buf.length, variant: vkey, full, thumb };
  } else {
    let img = sharp(buf, { failOn: "none" }).rotate();
    const meta = await img.metadata();
    let width = meta.autoOrient?.width ?? meta.width ?? 0;
    if (spec.crop && width) {
      const box = cropBox(width, meta.autoOrient?.height ?? meta.height ?? 0, spec.crop);
      // the crop runs on the rotated image: materialize it first (sharp applies extract before rotate otherwise)
      img = sharp(await img.toBuffer()).extract(box);
      width = box.width;
    }
    const variant = async (maxW, quality, suffix) => {
      const url = mediaUrl(stem, `${suffix}.${R.format}`);
      const info = await img.clone().resize({ width: maxW, withoutEnlargement: true })
        .webp({ quality, effort: R.effort, alphaQuality: R.alphaQuality }).toFile(outAbs(url));
      return { url, width: info.width, height: info.height, bytes: info.size };
    };
    const full = await variant(P.fullWidth, P.quality, "");
    // A source no wider than the thumb gets one file.
    const thumb = width > P.thumbWidth ? await variant(P.thumbWidth, P.thumbQuality, ".thumb") : full;
    entry = { mod, src, hash, bytesIn: buf.length, variant: vkey, full, thumb };
  }
  stats.processed++;
  stats.newIn += entry.bytesIn;
  stats.newOut += entry.full.bytes + (entry.thumb.url === entry.full.url ? 0 : entry.thumb.bytes);
  return entry;
}

const queue = [...jobs.entries()];
const next = {};
const t0 = Date.now();
let done = 0;
async function worker() {
  for (;;) {
    const item = queue.shift();
    if (!item) return;
    const [key, job] = item;
    try {
      next[key] = await processOne(key, job);
    } catch (e) {
      stats.failed++;
      // Keep what the last good run made: the stale sweep below then leaves its files alone.
      const prev = cache.entries[key];
      if (prev && variantOk(prev.full) && variantOk(prev.thumb)) next[key] = prev;
      console.error(`media: failed ${job.src}: ${e.message}${next[key] ? " (keeping its previous output)" : ""}`);
    }
    done++;
    if (process.stdout.isTTY && done % 25 === 0) process.stdout.write(`\r  ${done}/${jobs.size}`);
  }
}
await Promise.all(Array.from({ length: JOBS }, worker));
if (process.stdout.isTTY) process.stdout.write("\r");

// Keep entries of mods not in this run (--mod), drop the rest that vanished, and delete their files.
const keep = ONLY ? Object.fromEntries(Object.entries(cache.entries).filter(([, e]) => e.mod !== ONLY)) : {};
const live = new Set(Object.values({ ...keep, ...next }).flatMap((e) => [e.full.url, e.thumb.url]));
let removed = 0;
for (const [, e] of Object.entries(cache.entries)) {
  if (ONLY && e.mod !== ONLY) continue;
  for (const u of new Set([e.full.url, e.thumb.url])) {
    if (!live.has(u) && fs.existsSync(outAbs(u))) { fs.rmSync(outAbs(u)); removed++; }
  }
}
// Folders left empty (renamed output paths) go too.
const prune = (dir) => {
  for (const d of fs.readdirSync(dir, { withFileTypes: true })) if (d.isDirectory()) prune(path.join(dir, d.name));
  if (dir !== mediaRoot && fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
};
const mediaRoot = path.join(SITE, MEDIA_DIR);
if (fs.existsSync(mediaRoot)) prune(mediaRoot);
cache.entries = { ...keep, ...next };
fs.mkdirSync(path.dirname(cachePath), { recursive: true });
fs.writeFileSync(cachePath, JSON.stringify(cache, null, 1));

for (const e of Object.values(next)) {
  stats.bytesIn += e.bytesIn;
  stats.bytesOut += e.full.bytes + (e.thumb.url === e.full.url ? 0 : e.thumb.bytes);
}
const mb = (n) => `${(n / 1048576).toFixed(1)} MB`;
const secs = ((Date.now() - t0) / 1000).toFixed(1);
console.log(
  `media: ${jobs.size} sources from ${manifestFiles.length} manifest(s): ${stats.processed} processed, ` +
  `${stats.cached} cached, ${stats.failed} failed, ${removed} stale files removed (${secs} s, ${JOBS} jobs)`,
);
console.log(`media: this run ${mb(stats.newIn)} -> ${mb(stats.newOut)}; all media ${mb(stats.bytesIn)} -> ${mb(stats.bytesOut)} in ${MEDIA_DIR}/`);
if (stats.failed) process.exit(1);
