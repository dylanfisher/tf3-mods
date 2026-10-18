// Data files of sections, at /data/<mod-slug>/<section>/<file>: every file a section's kind publishes (KindDef.files),
// e.g. the data-explorer's tables, which its island fetches. Copied as they are at build time.
import fs from "node:fs";
import type { APIRoute } from "astro";
import { getSections } from "@/components/sections/resolve";
import { getMods } from "@/lib/mods";
import { repoPath } from "@/lib/repo";
import { assertSlug } from "@/lib/slug";

export function getStaticPaths() {
  return getMods().flatMap((mod) =>
    getSections(mod).flatMap(({ section, kind }) =>
      (kind.files?.({ mod, section }) ?? []).map((f) => ({
        params: { mod: mod.slug, section: section.slug, file: assertSlug(f.name, `${mod.id}/${section.slug} data file`) },
        props: { path: f.path },
      })),
    ),
  );
}

export const GET: APIRoute = ({ props }) =>
  new Response(fs.readFileSync(repoPath((props as { path: string }).path)), { headers: { "Content-Type": "application/json" } });
