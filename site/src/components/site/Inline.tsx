// Renders the inline markup of data text (parseInline in src/lib/format.ts: **bold** and `code`) as React nodes:
// never HTML, so a builder's or a note's text cannot inject markup. Static in Astro, usable in islands.
import { parseInline } from "@/lib/format";

export default function Inline({ text }: { text: string }) {
  return (
    <>
      {parseInline(text).map((r, i) => (r.bold ? <b key={i}>{r.text}</b> : r.code ? <code key={i}>{r.text}</code> : <span key={i}>{r.text}</span>))}
    </>
  );
}
