// Build-time access to the repo around site/. Only used in Astro frontmatter and build-time modules, never in client
// code. The repo root comes from TF3_REPO_ROOT, which astro.config.mjs sets from its own location (site/..) unless the
// environment already does; scripts/media.mjs finds it the same way from its file, so neither depends on the cwd.
import fs from "node:fs";
import path from "node:path";

const root = process.env.TF3_REPO_ROOT;
if (!root) throw new Error("TF3_REPO_ROOT is not set (astro.config.mjs sets it; run the build through astro)");

const REPO_ROOT = path.resolve(root);
export const SITE_ROOT = path.join(REPO_ROOT, "site");

export const repoPath = (rel: string) => path.join(REPO_ROOT, rel);

/**
 * A repo-relative JSON file: undefined when the file does not exist, an error naming the file when it cannot be read
 * or parsed (a broken data file fails the build instead of quietly showing nothing).
 */
export function readJson<T = unknown>(rel: string): T | undefined {
  const abs = repoPath(rel);
  if (!fs.existsSync(abs)) return undefined;
  try {
    return JSON.parse(fs.readFileSync(abs, "utf8")) as T;
  } catch (e) {
    throw new Error(`${rel}: ${(e as Error).message}`);
  }
}
