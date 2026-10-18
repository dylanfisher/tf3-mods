// Build time: a mod's changelog, read from its mod.io description (mods/<id>/_metadata/description.html, the
// "Changelog" section of branding/README.md: <h4>Revision N (YYYY-MM-DD)</h4> followed by a <ul> of <li> items).
// Read, never copied into the site: plain text items, the leading "New:" / "Changed:" / "Fixed:" in bold markup.
import fs from "node:fs";
import { repoPath } from "./repo.ts";

interface ChangelogEntry {
  revision: number;
  /** YYYY-MM-DD, or undefined for "(unreleased)" / "(dev, never uploaded)" headings */
  date?: string;
  /** the heading's text in parentheses when it is not a date */
  note?: string;
  /** inline markup (components/site/Inline.tsx) */
  items: string[];
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
const text = (html: string) =>
  html
    .replace(/<[^>]+>/g, "")
    .replace(/&(#\d+|#x[0-9a-f]+|\w+);/gi, (m, e: string) =>
      e[0] === "#" ? String.fromCodePoint(e[1].toLowerCase() === "x" ? parseInt(e.slice(2), 16) : Number(e.slice(1))) : ENTITIES[e.toLowerCase()] ?? m)
    .replace(/\s+/g, " ")
    .trim();
// Inline markup has no escape: a stray ** or ` in the description would become formatting, so drop them.
const plain = (s: string) => s.replace(/\*\*|`/g, "");

const cache = new Map<string, ChangelogEntry[]>();

/** Newest first, as in the description; [] when the mod has no description or no Changelog section. */
export function readChangelog(modId: string): ChangelogEntry[] {
  const hit = cache.get(modId);
  if (hit) return hit;
  const file = repoPath(`mods/${modId}/_metadata/description.html`);
  const out: ChangelogEntry[] = [];
  if (fs.existsSync(file)) {
    const html = fs.readFileSync(file, "utf8");
    const at = html.search(/<h2>\s*Changelog\s*<\/h2>/i);
    if (at >= 0) {
      const re = /<h4>\s*Revision\s+(\d+)\s*(?:\(([^)]*)\))?\s*<\/h4>\s*<ul>([\s\S]*?)<\/ul>/gi;
      re.lastIndex = at;
      for (let m = re.exec(html); m; m = re.exec(html)) {
        const paren = m[2]?.trim();
        const date = paren && /^\d{4}-\d{2}-\d{2}$/.test(paren) ? paren : undefined;
        const items = [...m[3].matchAll(/<li>([\s\S]*?)<\/li>/gi)].map((li) =>
          plain(text(li[1])).replace(/^(New|Changed|Fixed|Removed|Improved):/, "**$1:**"),
        );
        out.push({ revision: Number(m[1]), date, note: date ? undefined : paren, items });
      }
    }
  }
  cache.set(modId, out);
  return out;
}
