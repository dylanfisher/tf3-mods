// Generated placeholder art for a card's image slot when there is no image: the whole title set large (fitted to the
// slot, never cut off), over soft blurred color fields of the brand teal and the mod's accent (bg-mod-art: the
// --mod-accent its parent sets, else the warm run-1 tone) and a faint grid.
// Deterministic per title (the field positions come from a hash), pure markup on theme tokens (no stylesheet),
// legible in light and dark. Plain React without state or effects: Astro renders it to static HTML (SectionCard,
// ModCover), islands use it too (CompareList). The parent decides the size; the art fills it (give it an aspect
// ratio via `className` and the same ratio as `aspect`).
import { cn } from "@/lib/utils";

interface TitleArtProps {
  title: string;
  className?: string;
  /** accessible label; default: decorative (aria-hidden), since the card shows the title anyway */
  label?: string;
  /** width / height of the slot (default 16 / 9): picks the line breaks that give the biggest type */
  aspect?: number;
}

// Type fitting without measuring: a bold sans glyph averages ~0.6 em with the tight tracking below; 0.66 keeps
// most wide words inside (only all-"M"/"W" titles may still touch the padding). The box is a size container
// (cqw and cqh are its own width and height). The type takes at most FIT_W of the width and FIT_H of the height (the rest is padding).
// Font size = min(width limit in cqw, height limit in cqh), so it fits whatever size the slot renders at.
const EM_PER_CHAR = 0.66;
const LINE = 0.95;
const FIT_W = 0.84;
const FIT_H = 0.62;

/** FNV-1a: a stable 32-bit hash of the title, the art's seed. */
function hash(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** Balanced split of the words into n lines (greedy by characters). */
function split(words: string[], n: number): string[] {
  const total = words.join(" ").length;
  const lines: string[] = [];
  let cur: string[] = [];
  let used = 0;
  for (const w of words) {
    const target = (total / n) * (lines.length + 1);
    const len = used + [...cur, w].join(" ").length;
    if (cur.length && lines.length < n - 1 && len > target + w.length / 2) {
      lines.push(cur.join(" "));
      used += cur.join(" ").length + 1;
      cur = [];
    }
    cur.push(w);
  }
  lines.push(cur.join(" "));
  return lines;
}

/** Line breaks and font size limits that fit the whole title into a slot of the given aspect. */
function fit(title: string, aspect: number) {
  const words = title.trim().split(/\s+/).filter(Boolean);
  let best = { lines: [title], cqw: 10, cqh: 10, size: 0 };
  for (let n = 1; n <= Math.min(3, words.length); n++) {
    const lines = split(words, n);
    if (n > 1 && lines.some((l) => l.length < 3)) continue; // no line of just "&" or "of"
    const chars = Math.max(...lines.map((l) => l.length));
    const cqw = (FIT_W * 100) / (chars * EM_PER_CHAR); // % of the width
    const cqh = (FIT_H * 100) / (n * LINE); // % of the height
    const size = Math.min(cqw, cqh / aspect); // both in % of the width, to compare
    if (size > best.size + 0.5) best = { lines, cqw, cqh, size };
  }
  return best;
}

export default function TitleArt({ title, className, label, aspect = 16 / 9 }: TitleArtProps) {
  const h = hash(title);
  const pick = (shift: number, lo: number, hi: number) => lo + (((h >>> shift) & 0xff) / 255) * (hi - lo);
  // Two big fields on opposite sides, one small highlight; percentages of the box.
  const f1 = { left: `${pick(0, -20, 15)}%`, top: `${pick(8, -45, 5)}%` };
  const f2 = { left: `${pick(16, 45, 75)}%`, top: `${pick(24, 10, 55)}%` };
  const f3 = { left: `${pick(4, 25, 55)}%`, top: `${pick(12, 50, 80)}%` };
  const { lines, cqw, cqh } = fit(title, aspect);
  const grid = `ta-grid-${h.toString(36)}`;
  return (
    <div
      className={cn("relative isolate [container-type:size] w-full overflow-hidden bg-chip select-none", className)}
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      <div className="absolute size-[75cqw] rounded-full bg-brand opacity-55 blur-[9cqw] dark:opacity-40" style={f1} />
      <div className="absolute size-[65cqw] rounded-full bg-mod-art opacity-45 blur-[10cqw] dark:opacity-35" style={f2} />
      <div className="absolute size-[30cqw] rounded-full bg-brand-text opacity-35 blur-[6cqw] dark:opacity-30" style={f3} />
      {/* faint grid, fading out toward the top right */}
      <svg className="absolute inset-0 size-full text-foreground opacity-[0.07] [mask-image:linear-gradient(to_top_right,black_30%,transparent_85%)]" aria-hidden="true">
        <defs>
          <pattern id={grid} width="16" height="16" patternUnits="userSpaceOnUse">
            <path d="M16 0H0V16" fill="none" stroke="currentColor" strokeWidth="1" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill={`url(#${grid})`} />
      </svg>
      <div
        className="absolute inset-x-0 bottom-0 px-[7cqw] pb-[6cqh] leading-[0.95] font-extrabold tracking-[-0.04em] whitespace-nowrap"
        style={{ fontSize: `min(${cqw.toFixed(2)}cqw, ${cqh.toFixed(2)}cqh)` }}
      >
        {lines.map((l, i) => (
          <span key={i} className="block bg-gradient-to-br from-foreground from-30% to-brand-text bg-clip-text pb-[0.06em] text-transparent opacity-85">{l}</span>
        ))}
      </div>
    </div>
  );
}
