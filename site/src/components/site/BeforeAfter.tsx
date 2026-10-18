// Two images over each other, split by a line: press and drag anywhere on the images (the whole height, not only the
// handle) to move it; keyboards use the visually hidden range input (arrow keys; the handle shows its focus). before / after, run A / run B. Vertical swipes still scroll
// the page on touch screens. The images should share a view (same camera); both fill the box (object-cover). Used by the run
// comparison viewer (ShotSlider) and by story pages (sections/story). Labels are plain text.
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useRef, useState, type CSSProperties, type ReactNode } from "react";
import { cn } from "@/lib/utils";

interface SliderImage {
  /** the image element (an <img> or a responsive picture), filling its box; none: only the label shows */
  render?: (props: { className: string; style?: CSSProperties }) => ReactNode;
  label: string;
}

export default function BeforeAfter({ left, right, className, aspect = "aspect-video", ratio }: {
  /** shown left of the line (clipped to it) */
  left?: SliderImage;
  /** shown right of the line (underneath) */
  right?: SliderImage;
  className?: string;
  /** Tailwind aspect class of the box */
  aspect?: string;
  /** width / height of the box instead of `aspect` (the images' own ratio) */
  ratio?: number;
}) {
  const [pos, setPos] = useState(50);
  const box = useRef<HTMLDivElement>(null);
  const drag = useRef(false);
  const move = (x: number) => {
    const r = box.current?.getBoundingClientRect();
    if (r && r.width) setPos(Math.max(0, Math.min(100, ((x - r.left) / r.width) * 100)));
  };
  const label = "absolute top-2 max-w-[calc(50%-12px)] truncate rounded-md bg-black/55 px-2 py-0.5 text-meta font-semibold text-white";
  const fill = "absolute inset-0 block size-full object-cover";
  return (
    <div
      ref={box}
      className={cn("relative mx-auto cursor-ew-resize touch-pan-y overflow-hidden rounded-lg border border-border bg-chip select-none [&_img]:pointer-events-none", !ratio && aspect, className)}
      style={ratio ? { aspectRatio: String(ratio) } : undefined}
      onPointerDown={(e) => {
        if ((e.target as HTMLElement).tagName === "INPUT" || e.button !== 0) return;
        e.preventDefault(); // no native image drag or text selection
        e.currentTarget.setPointerCapture(e.pointerId);
        drag.current = true;
        move(e.clientX);
      }}
      onPointerMove={(e) => drag.current && move(e.clientX)}
      onPointerUp={() => { drag.current = false; }}
      onPointerCancel={() => { drag.current = false; }}
      onDragStart={(e) => e.preventDefault()}
    >
      {right?.render?.({ className: fill })}
      {left?.render?.({ className: fill, style: { clipPath: `inset(0 ${100 - pos}% 0 0)` } })}
      {left && <span className={cn(label, "left-2")}>{left.label}</span>}
      {right && <span className={cn(label, "right-2")}>{right.label}</span>}
      <input
        type="range"
        min={0}
        max={100}
        value={Math.round(pos)}
        onChange={(e) => setPos(Number(e.currentTarget.value))}
        aria-label="Slider position"
        className="peer sr-only"
      />
      <div className="pointer-events-none absolute inset-y-0 w-0.5 -translate-x-px bg-white/90 shadow-[0_0_0_1px_rgba(0,0,0,.25)] peer-focus-visible:[&>span]:ring-2 peer-focus-visible:[&>span]:ring-brand" style={{ left: `${pos}%` }}>
        <span aria-hidden className="absolute top-1/2 left-1/2 flex size-7 -translate-1/2 items-center justify-center rounded-full bg-white/70 text-neutral-800 backdrop-blur-md shadow-[0_1px_4px_rgba(0,0,0,.35),0_0_0_1px_rgba(0,0,0,.08)]">
          <ChevronLeft className="-mr-1 size-3.5" strokeWidth={2.5} />
          <ChevronRight className="-ml-1 size-3.5" strokeWidth={2.5} />
        </span>
      </div>
    </div>
  );
}
