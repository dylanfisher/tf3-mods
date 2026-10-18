// The one lightbox of the site: mounted once per page (BaseLayout), it opens on a click on any element marked with
// lightboxAttrs() (src/lib/lightbox.ts) and steps through the visible marked images of the same group
// ([data-lightbox-group], else the whole page) in page order. The image sits on a blurred backdrop with its title,
// n / total, previous / next (buttons and the arrow keys) and an optional link to the page that tells more. No animation.
import { ChevronLeft, ChevronRight, XIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { Dialog as DialogPrimitive } from "@base-ui/react/dialog";
import { Button } from "@/components/ui/button";
import { LB, type LightboxItem, readItem } from "@/lib/lightbox";

const visible = (el: HTMLElement) => el.getClientRects().length > 0;

export default function Lightbox() {
  const [items, setItems] = useState<LightboxItem[]>([]);
  const [open, setOpen] = useState<number | null>(null);
  const cur = open != null ? items[open] : null;
  const step = (d: number) => { if (open != null && items.length) setOpen((open + d + items.length) % items.length); };

  // one delegated listener for every marked element, including those islands render later
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      const el = (e.target as Element | null)?.closest<HTMLElement>(`[${LB.src}]`);
      if (!el) return;
      e.preventDefault();
      const scope = el.closest(`[${LB.group}]`) ?? document;
      const els = [...scope.querySelectorAll<HTMLElement>(`[${LB.src}]`)].filter((x) => x === el || visible(x));
      setItems(els.map(readItem));
      setOpen(Math.max(0, els.indexOf(el)));
    };
    document.addEventListener("click", onClick);
    return () => document.removeEventListener("click", onClick);
  }, []);

  useEffect(() => {
    if (open == null) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowRight") step(1);
      else if (e.key === "ArrowLeft") step(-1);
    };
    // capture: the dialog's focus handling keeps key events from bubbling to the window
    document.addEventListener("keydown", onKey, true);
    return () => document.removeEventListener("keydown", onKey, true);
  }); // eslint-disable-line react-hooks/exhaustive-deps

  const many = items.length > 1;
  return (
    <DialogPrimitive.Root open={cur != null} onOpenChange={(o) => { if (!o) setOpen(null); }}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Backdrop className="fixed inset-0 z-50 bg-background/30 backdrop-blur-md" />
        <DialogPrimitive.Popup
          className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-2 p-4 outline-none sm:px-16"
          onClick={(e) => { if (e.target === e.currentTarget) setOpen(null); }}
        >
          {cur && (
            <>
              <img
                key={cur.src}
                src={cur.src}
                alt={cur.title}
                className="block h-auto max-h-[calc(100dvh-7rem)] w-auto max-w-full rounded-md shadow-2xl"
              />
              <div className="flex max-w-full items-baseline gap-3 text-dense">
                <DialogPrimitive.Title className="min-w-0 truncate font-medium">{cur.title}</DialogPrimitive.Title>
                {many && <span className="shrink-0 text-meta text-muted-foreground tabular-nums">{(open ?? 0) + 1} / {items.length}</span>}
                {cur.href && <a href={cur.href} className="shrink-0 text-brand-text hover:underline">{cur.hrefLabel ?? "More about this"} →</a>}
              </div>
              {many && (
                <>
                  <Button variant="outline" size="icon" aria-label="Previous image" className="absolute top-[calc(50%-1rem)] left-2 rounded-full bg-background/80" onClick={() => step(-1)}><ChevronLeft /></Button>
                  <Button variant="outline" size="icon" aria-label="Next image" className="absolute top-[calc(50%-1rem)] right-2 rounded-full bg-background/80" onClick={() => step(1)}><ChevronRight /></Button>
                </>
              )}
              <DialogPrimitive.Close render={<Button variant="outline" size="icon" className="absolute top-3 right-3 rounded-full bg-background/80" />}>
                <XIcon /><span className="sr-only">Close</span>
              </DialogPrimitive.Close>
            </>
          )}
        </DialogPrimitive.Popup>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
