// @ts-check
import { defineConfig } from "astro/config";
import react from "@astrojs/react";
import mdx from "@astrojs/mdx";
import tailwindcss from "@tailwindcss/vite";
import { fileURLToPath } from "node:url";

// The repo around site/, for build-time reads (src/lib/repo.ts): from this file's location, not the cwd.
process.env.TF3_REPO_ROOT ??= fileURLToPath(new URL("..", import.meta.url));

/** Rollup plugin: "_" in output file names (entries, chunks) becomes "-". */
function dashedFileNames() {
  /** @param {string | ((c: any) => string) | undefined} pattern */
  const wrap = (pattern) => (pattern == null ? pattern : (/** @type {any} */ c) => (typeof pattern === "function" ? pattern(c) : pattern).replace(/\[name\]/g, c.name).replace(/_/g, "-"));
  return {
    name: "dashed-file-names",
    /** @param {any} o */
    outputOptions(o) {
      return { ...o, entryFileNames: wrap(o.entryFileNames), chunkFileNames: wrap(o.chunkFileNames) };
    },
  };
}

/** The custom domain: the only place it is written (scripts/deploy.sh writes the Pages CNAME from it). */
export const SITE_URL = "https://tf3.dylanfisher.com";

// Static site served from the root of the custom domain.
export default defineConfig({
  devToolbar: { enabled: false },
  site: SITE_URL,
  base: "/",
  output: "static",
  // Built assets at /assets/ instead of /_astro/: no URL of the site has an underscore (src/lib/slug.ts).
  build: { assets: "assets" },
  trailingSlash: "ignore",
  integrations: [react(), mdx()],
  // No "_" in built file names either: base36 hashes (Vite's base64 ones can contain "_", input.DZvocEo_.js) and chunk
  // names with "_" as "-" (a hoisted script with imports is named ThemeToggle.astro_astro_type_script_...). A Rollup
  // outputOptions hook, because Astro sets its own entry names after the user config.
  vite: { plugins: [tailwindcss(), dashedFileNames()], build: { rollupOptions: { output: { hashCharacters: "base36" } } } },
});
