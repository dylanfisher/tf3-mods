// The one class merger of the site (shadcn's components and ours import cn from here). The site's own font-size
// steps (theme.css --text-*) are registered as font sizes: without that, cn("text-hint text-muted-foreground") would
// take text-hint for a text color and drop it.
import { createCn } from "cn/config";

const TEXT_SIZES = ["tag", "meta", "hint", "dense", "subhead", "lead", "display"];

export const cn = createCn({ extend: { classGroups: { "font-size": [{ text: TEXT_SIZES }] } } });
