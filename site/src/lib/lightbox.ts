// Marking images for the site's lightbox (components/site/Lightbox.tsx, mounted once in BaseLayout). Spread
// lightboxAttrs() on the clickable element (a button, a link to the full image, or the <img> itself); put
// lightboxGroup on a container so previous / next stay within it (default: every marked image on the page).
export const LB = {
  src: "data-lightbox",
  title: "data-lightbox-title",
  href: "data-lightbox-href",
  hrefLabel: "data-lightbox-href-label",
  group: "data-lightbox-group",
} as const;

export interface LightboxItem {
  src: string;
  title: string;
  /** a page about the image (a link under the title) */
  href?: string;
  hrefLabel?: string;
}

export const lightboxAttrs = (it: LightboxItem): Record<string, string> => ({
  [LB.src]: it.src,
  [LB.title]: it.title,
  ...(it.href ? { [LB.href]: it.href } : {}),
  ...(it.hrefLabel ? { [LB.hrefLabel]: it.hrefLabel } : {}),
});

export const lightboxGroup = { [LB.group]: "" } as Record<string, string>;

export const readItem = (el: HTMLElement): LightboxItem => ({
  src: el.getAttribute(LB.src) ?? "",
  title: el.getAttribute(LB.title) ?? "",
  href: el.getAttribute(LB.href) ?? undefined,
  hrefLabel: el.getAttribute(LB.hrefLabel) ?? undefined,
});
