// Number, text and markup helpers shared by build-time code (manifests, loaders) and islands. Plain TypeScript with
// only erasable syntax: manifests import it, and scripts/media.mjs imports the manifests with Node directly.

/** Grouped number with exactly `d` decimals ("1,234.5"); "-" for null, undefined, "" or NaN. */
export function fmt(v: unknown, d = 0): string {
  if (v == null || v === "") return "-";
  const n = Number(v);
  if (Number.isNaN(n)) return "-";
  return n.toLocaleString("en-US", { maximumFractionDigits: d, minimumFractionDigits: d });
}

/** "x1.23" ratio of two numbers, "-" when either is missing or b is 0. */
export const ratio = (a: number | null | undefined, b: number | null | undefined): string =>
  a == null || b == null || !b ? "-" : "x" + fmt(a / b, 2);

/** The word for a count: plural(1, "run", "runs") -> "run". */
export const plural = (n: number, one: string, many: string): string => (n === 1 ? one : many);

/** First letter upper case. */
export const cap = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

/** A name without its leading "01-" / "2x3-" sort prefix, dashes as spaces ("01-old-town" -> "old town"). */
export const humanName = (s: string): string => s.replace(/^[\dx]+-/, "").replace(/[-_]+/g, " ");

/**
 * Inline markup for text that comes from data files (hand-written notes, page footers): **bold** and `code`, nothing
 * else (no HTML; a "<" stays a "<"). Returns the runs to render (components/site/Inline.tsx).
 */
interface InlineRun { text: string; bold?: boolean; code?: boolean }

export function parseInline(s: string): InlineRun[] {
  const out: InlineRun[] = [];
  const re = /\*\*(.+?)\*\*|`([^`]+)`/g;
  let at = 0;
  for (let m = re.exec(s); m; m = re.exec(s)) {
    if (m.index > at) out.push({ text: s.slice(at, m.index) });
    out.push(m[1] != null ? { text: m[1], bold: true } : { text: m[2], code: true });
    at = m.index + m[0].length;
  }
  if (at < s.length) out.push({ text: s.slice(at) });
  return out;
}
