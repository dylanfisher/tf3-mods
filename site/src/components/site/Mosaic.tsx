// A wall of images in justified rows (every row filled edge to edge, each image at its own aspect ratio), the caption
// on hover or focus (images never move), and a click opens the site lightbox (lib/lightbox.ts; previous / next stay
// within the wall). Used by the story block "mosaic", the image grid's Wall view and the landing highlights. The first image can be shown large (`lead`).
import { lightboxAttrs, lightboxGroup } from "@/lib/lightbox";
import { cn } from "@/lib/utils";

export interface MosaicImage {
  id: string;
  title: string;
  full: string;
  /** a page about the image (linked in the lightbox) */
  href?: string;
  hrefLabel?: string;
  thumb: string;
  /** thumb size (its ratio sets the tile's) */
  w: number;
  h: number;
  /** full width (srcset) */
  fw: number;
}

type MosaicSize = "s" | "m" | "l";
/** target row height in CSS px per size */
const ROW: Record<MosaicSize, number> = { s: 96, m: 150, l: 240 };

export default function Mosaic({ images, size = "m", lead = false, captions = "hover" }: {
  images: MosaicImage[];
  size?: MosaicSize;
  /** first image across the full width above the rest */
  lead?: boolean;
  /** "hover": caption on hover / focus; "none": the title only in the lightbox */
  captions?: "hover" | "none";
}) {
  const row = ROW[size];
  const tile = (img: MosaicImage, big = false) => {
    const ratio = img.w / img.h || 1.6;
    return (
      <button
        key={img.id}
        type="button"
        {...lightboxAttrs({ src: img.full, title: img.title, href: img.href, hrefLabel: img.hrefLabel })}
        title={img.title}
        className={cn("group relative min-w-0 overflow-hidden rounded-md border border-border bg-chip hover:border-brand focus-visible:border-brand", big && "w-full")}
        style={big ? { aspectRatio: ratio } : { aspectRatio: ratio, flexGrow: ratio, flexBasis: `${Math.round(ratio * row)}px` }}
      >
        <img
          src={img.thumb}
          srcSet={img.fw > img.w ? `${img.thumb} ${img.w}w, ${img.full} ${img.fw}w` : undefined}
          sizes={big ? "(min-width: 1140px) 1100px, 100vw" : `${Math.round(ratio * row * 1.25)}px`}
          width={img.w}
          height={img.h}
          alt={img.title}
          loading={big ? "eager" : "lazy"}
          decoding="async"
          className="block h-full w-full object-cover"
        />
        {captions === "hover" && (
          <span className="pointer-events-none absolute inset-x-0 bottom-0 truncate bg-background/85 px-2 py-1 text-left text-tag text-foreground opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100">
            {img.title}
          </span>
        )}
      </button>
    );
  };
  const rest = lead ? images.slice(1) : images;
  return (
    <div className="flex min-w-0 flex-col gap-1.5" {...lightboxGroup}>
      {lead && images[0] && tile(images[0], true)}
      {rest.length > 0 && (
        <div className="flex min-w-0 flex-wrap gap-1.5">
          {rest.map((img) => tile(img))}
          {/* keeps the last row's images at their row height instead of stretching them across */}
          <span aria-hidden className="h-0" style={{ flexGrow: 1000, flexBasis: 0 }} />
        </div>
      )}
    </div>
  );
}
